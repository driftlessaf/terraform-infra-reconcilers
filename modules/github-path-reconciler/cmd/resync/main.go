/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"crypto/sha256"
	"encoding/binary"
	"fmt"
	"net/http"
	"os/signal"
	"syscall"
	"time"

	"github.com/chainguard-dev/clog"
	_ "github.com/chainguard-dev/clog/gcp/init"
	"github.com/google/go-github/v84/github"
	"github.com/sethvargo/go-envconfig"
	"golang.org/x/oauth2"
	"golang.org/x/sync/errgroup"

	"chainguard.dev/driftlessaf/reconcilers/githubreconciler"
	"chainguard.dev/driftlessaf/workqueue"
	"chainguard.dev/terraform-infra-reconcilers/modules/github-path-reconciler/internal/patterns"
	"github.com/chainguard-dev/terraform-infra-common/pkg/httpmetrics"
)

var env = envconfig.MustProcess(context.Background(), &struct {
	// Identity string used as the reconciler display name and the config file
	// name (.{identity}.yaml) in repos without explicit REPOS_CONFIG entries.
	Identity string `env:"OCTO_IDENTITY"`

	// Octo STS identity — used when AppID is zero.
	OctoSTSIdentity string `env:"OCTO_STS_IDENTITY"`

	// GitHub App credentials — when AppID is non-zero, these override OctoSTSIdentity.
	AppID  int64  `env:"GITHUB_APP_ID"`
	AppKey string `env:"GITHUB_APP_KEY"`

	// Workqueue configuration
	WorkqueueAddr string `env:"WORKQUEUE_ADDR,required"`

	// Repos config (JSON array of {owner, repo, path_patterns}). When empty and
	// AppID is non-zero, repos are discovered from the app's installations.
	ReposConfig string `env:"REPOS_CONFIG,required"`

	// Period in minutes for time bucketing
	PeriodMinutes int `env:"PERIOD_MINUTES,required"`
}{})

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	go httpmetrics.ServeMetrics()
	defer httpmetrics.SetupTracer(ctx)()
	httpmetrics.SetBuckets(map[string]string{
		"api.github.com": "github",
		"octo-sts.dev":   "octosts",
	})

	// Parse repos config
	repoConfigs, err := patterns.ParseRepoConfigs(env.ReposConfig)
	if err != nil {
		clog.FatalContextf(ctx, "Failed to parse repos config: %v", err)
	}

	// Set up workqueue client
	wqClient, err := workqueue.NewWorkqueueClient(ctx, env.WorkqueueAddr)
	if err != nil {
		clog.FatalContextf(ctx, "Failed to create workqueue client: %v", err)
	}
	defer wqClient.Close()

	var app *githubreconciler.App
	if env.AppID != 0 {
		app, err = githubreconciler.NewApp(ctx, env.AppID, env.AppKey)
		if err != nil {
			clog.FatalContextf(ctx, "Failed to create GitHub App: %v", err)
		}
	}

	clientCache := buildClientCache(app)

	// When no explicit repos are configured and we have app credentials,
	// discover repos from the app's installations at runtime.
	var appClient *github.Client
	if len(repoConfigs) == 0 && app != nil {
		appClient = app.Client()
	}

	handler := &cronHandler{
		clientCache:   clientCache,
		appClient:     appClient,
		identity:      env.Identity,
		wqClient:      wqClient,
		repoConfigs:   repoConfigs,
		periodMinutes: env.PeriodMinutes,
	}

	clog.InfoContextf(ctx, "Starting cron run for %d explicit repositories", len(repoConfigs))
	if err := handler.run(ctx); err != nil {
		clog.FatalContextf(ctx, "Cron run failed: %v", err)
	}
	clog.InfoContextf(ctx, "Cron run complete")
}

type cronHandler struct {
	clientCache   *githubreconciler.ClientCache
	appClient     *github.Client // non-nil when repos are discovered from the app
	identity      string
	wqClient      workqueue.Client
	repoConfigs   []patterns.RepoConfig
	periodMinutes int
}

func (h *cronHandler) run(ctx context.Context) error {
	configs := h.repoConfigs

	// When no explicit repos are configured, discover repos from the app's installations.
	if len(configs) == 0 && h.appClient != nil {
		discovered, err := h.discoverRepoConfigs(ctx)
		if err != nil {
			return fmt.Errorf("discover repos from app installations: %w", err)
		}
		configs = discovered
		clog.InfoContextf(ctx, "Discovered %d repositories from app installations", len(configs))
	}

	var eg errgroup.Group
	for _, cfg := range configs {
		eg.Go(func() error {
			return h.runRepo(ctx, cfg)
		})
	}
	return eg.Wait()
}

// discoverRepoConfigs lists all repos accessible to the app across its
// installations, fetches .{identity}.yaml from each, and returns the configs
// for repos that have the file.
func (h *cronHandler) discoverRepoConfigs(ctx context.Context) ([]patterns.RepoConfig, error) {
	var configs []patterns.RepoConfig

	// List all app installations using the app-level JWT client.
	installPage := 1
	for installPage != 0 {
		installs, installsResp, err := h.appClient.Apps.ListInstallations(ctx, &github.ListOptions{
			Page:    installPage,
			PerPage: 100,
		})
		if err != nil {
			return nil, fmt.Errorf("list app installations: %w", err)
		}

		for _, install := range installs {
			org := install.GetAccount().GetLogin()

			// Get an installation-scoped client for this org, then list its repos.
			// Apps.ListRepos uses GET /installation/repositories which requires the
			// installation token (not the app JWT). The empty repo string requests
			// an org-scoped token rather than a repo-scoped one, which is needed
			// to enumerate all repositories under the installation.
			installClient, err := h.clientCache.Get(ctx, org, "")
			if err != nil {
				clog.WarnContextf(ctx, "Failed to get client for installation %s, skipping: %v", org, err)
				continue
			}

			repoPage := 1
			for repoPage != 0 {
				result, reposResp, err := installClient.Apps.ListRepos(ctx, &github.ListOptions{
					Page:    repoPage,
					PerPage: 100,
				})
				if err != nil {
					clog.WarnContextf(ctx, "Failed to list repos for installation %s, skipping: %v", org, err)
					break
				}
				for _, repo := range result.Repositories {
					owner := repo.GetOwner().GetLogin()
					name := repo.GetName()
					cfg, ok, err := h.fetchRepoConfig(ctx, owner, name, "")
					if err != nil {
						clog.WarnContextf(ctx, "Failed to fetch config for %s/%s, skipping: %v", owner, name, err)
						continue
					}
					if ok {
						configs = append(configs, cfg)
					}
				}
				repoPage = reposResp.NextPage
			}
		}
		installPage = installsResp.NextPage
	}

	return configs, nil
}

// fetchRepoConfig fetches .{identity}.yaml from the repo at the given ref
// (or the default branch if ref is empty). Returns (config, true, nil) if
// found, (zero, false, nil) if the file does not exist, or an error.
func (h *cronHandler) fetchRepoConfig(ctx context.Context, owner, repo, ref string) (patterns.RepoConfig, bool, error) {
	if h.identity == "" {
		return patterns.RepoConfig{}, false, nil
	}

	ghClient, err := h.clientCache.Get(ctx, owner, repo)
	if err != nil {
		return patterns.RepoConfig{}, false, err
	}

	filename := "." + h.identity + ".yaml"
	opts := &github.RepositoryContentGetOptions{Ref: ref}
	file, _, resp, err := ghClient.Repositories.GetContents(ctx, owner, repo, filename, opts)
	if err != nil {
		if resp != nil && resp.StatusCode == http.StatusNotFound {
			return patterns.RepoConfig{}, false, nil
		}
		return patterns.RepoConfig{}, false, fmt.Errorf("fetch %s from %s/%s: %w", filename, owner, repo, err)
	}

	decoded, err := file.GetContent()
	if err != nil {
		return patterns.RepoConfig{}, false, fmt.Errorf("decode %s from %s/%s: %w", filename, owner, repo, err)
	}
	content := []byte(decoded)

	cfg, err := patterns.ParseRepoConfigFile(content, owner, repo)
	if err != nil {
		return patterns.RepoConfig{}, false, err
	}
	return cfg, true, nil
}

func (h *cronHandler) runRepo(ctx context.Context, cfg patterns.RepoConfig) error {
	runTimestamp := time.Now().Unix()

	ctx = clog.WithValues(ctx, "owner", cfg.Owner, "repo", cfg.Repo)
	clog.InfoContextf(ctx, "Starting resync")

	ghClient, err := h.clientCache.Get(ctx, cfg.Owner, cfg.Repo)
	if err != nil {
		return fmt.Errorf("failed to get GitHub client for %s/%s: %w", cfg.Owner, cfg.Repo, err)
	}

	// Get the repository to determine the default branch
	repo, _, err := ghClient.Repositories.Get(ctx, cfg.Owner, cfg.Repo)
	if err != nil {
		return fmt.Errorf("failed to get repository %s/%s: %w", cfg.Owner, cfg.Repo, err)
	}
	defaultBranch := repo.GetDefaultBranch()

	// Get repository tree at default branch
	tree, _, err := ghClient.Git.GetTree(ctx, cfg.Owner, cfg.Repo, defaultBranch, true)
	if err != nil {
		return fmt.Errorf("failed to get repository tree for %s/%s: %w", cfg.Owner, cfg.Repo, err)
	}

	// Accumulate unique keys
	keySet := make(map[string]struct{})
	for _, entry := range tree.Entries {
		if entry.GetType() != "blob" {
			continue
		}
		if key := cfg.MatchPath(entry.GetPath()); key != "" {
			url := fmt.Sprintf("https://github.com/%s/%s/blob/%s/%s", cfg.Owner, cfg.Repo, defaultBranch, key)
			keySet[url] = struct{}{}
		}
	}

	// Enqueue all unique keys with their computed delays
	eg, egCtx := errgroup.WithContext(ctx)
	for url := range keySet {
		eg.Go(func() error {
			delay := h.computeDelay(url, runTimestamp)
			_, err := h.wqClient.Process(egCtx, &workqueue.ProcessRequest{
				Key:          url,
				Priority:     0,
				DelaySeconds: int64(delay.Seconds()),
			})
			if err != nil {
				clog.ErrorContextf(egCtx, "Failed to process key %q: %v", url, err)
				return err
			}
			clog.InfoContextf(egCtx, "Enqueued %q with delay %v", url, delay)
			return nil
		})
	}

	if err := eg.Wait(); err != nil {
		return fmt.Errorf("failed to enqueue keys for %s/%s: %w", cfg.Owner, cfg.Repo, err)
	}

	clog.InfoContextf(ctx, "Enqueued %d keys", len(keySet))
	return nil
}

func (h *cronHandler) computeDelay(key string, runTimestamp int64) time.Duration {
	// Hash the key + timestamp to get a consistent bucket.
	// We include runTimestamp in the hash so that we don't end up with the same
	// key ordering every single time things run.
	hashInput := fmt.Sprintf("%s-%d", key, runTimestamp)
	hash := sha256.Sum256([]byte(hashInput))
	hashValue := binary.BigEndian.Uint64(hash[:8])

	// Compute bucket (periodMinutes is validated to be 60-1440, so conversion is safe)
	bucket := int(hashValue % uint64(h.periodMinutes)) //nolint:gosec // G115: periodMinutes validated range

	return time.Duration(bucket) * time.Minute
}

func buildClientCache(app *githubreconciler.App) *githubreconciler.ClientCache {
	if app != nil {
		return githubreconciler.NewClientCache(app.TokenSourceFunc())
	}
	return githubreconciler.NewClientCache(func(ctx context.Context, org, repo string) (oauth2.TokenSource, error) {
		return githubreconciler.NewRepoTokenSource(ctx, env.OctoSTSIdentity, org, repo), nil
	})
}
