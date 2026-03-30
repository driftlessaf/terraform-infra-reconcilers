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
	"os/signal"
	"syscall"
	"time"

	"github.com/chainguard-dev/clog"
	_ "github.com/chainguard-dev/clog/gcp/init"
	"github.com/sethvargo/go-envconfig"
	"golang.org/x/oauth2"
	"golang.org/x/sync/errgroup"

	"chainguard.dev/driftlessaf/reconcilers/githubreconciler"
	"chainguard.dev/driftlessaf/workqueue"
	"chainguard.dev/terraform-infra-reconcilers/modules/github-path-reconciler/internal/patterns"
	"github.com/chainguard-dev/terraform-infra-common/pkg/httpmetrics"
)

var env = envconfig.MustProcess(context.Background(), &struct {
	// Octo STS configuration
	OctoSTSIdentity string `env:"OCTO_STS_IDENTITY,required"`

	// Workqueue configuration
	WorkqueueAddr string `env:"WORKQUEUE_ADDR,required"`

	// Repos config (JSON array of {owner, repo, path_patterns})
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

	clientCache := githubreconciler.NewClientCache(func(ctx context.Context, org, repo string) (oauth2.TokenSource, error) {
		return githubreconciler.NewRepoTokenSource(ctx, env.OctoSTSIdentity, org, repo), nil
	})

	handler := &cronHandler{
		clientCache:   clientCache,
		wqClient:      wqClient,
		repoConfigs:   repoConfigs,
		periodMinutes: env.PeriodMinutes,
	}

	clog.InfoContextf(ctx, "Starting cron run for %d repositories", len(repoConfigs))
	if err := handler.run(ctx); err != nil {
		clog.FatalContextf(ctx, "Cron run failed: %v", err)
	}
	clog.InfoContextf(ctx, "Cron run complete")
}

type cronHandler struct {
	clientCache   *githubreconciler.ClientCache
	wqClient      workqueue.Client
	repoConfigs   []patterns.RepoConfig
	periodMinutes int
}

func (h *cronHandler) run(ctx context.Context) error {
	eg, egCtx := errgroup.WithContext(ctx)
	for _, cfg := range h.repoConfigs {
		eg.Go(func() error {
			return h.runRepo(egCtx, cfg)
		})
	}
	return eg.Wait()
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
