/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"fmt"
	"net/http"
	"os/signal"
	"strings"
	"syscall"

	"github.com/chainguard-dev/clog"
	_ "github.com/chainguard-dev/clog/gcp/init"
	cloudevents "github.com/cloudevents/sdk-go/v2"
	"github.com/google/go-github/v88/github"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/sethvargo/go-envconfig"
	"golang.org/x/oauth2"
	"golang.org/x/sync/errgroup"

	"chainguard.dev/driftlessaf/reconcilers/githubreconciler"
	"chainguard.dev/driftlessaf/workqueue"
	"chainguard.dev/terraform-infra-reconcilers/modules/github-path-reconciler/internal/patterns"
	"github.com/chainguard-dev/terraform-infra-common/pkg/httpmetrics"
)

var env = envconfig.MustProcess(context.Background(), &struct {
	Port int `env:"PORT,default=8080"`

	// Workqueue configuration
	WorkqueueAddr string `env:"WORKQUEUE_ADDR,required"`

	// Repos config (JSON array of {owner, repo, path_patterns})
	ReposConfig string `env:"REPOS_CONFIG,required"`

	// Identity string used as the reconciler display name and the config file
	// name (.{identity}.yaml) for repos without explicit REPOS_CONFIG entries.
	Identity string `env:"OCTO_IDENTITY"`

	// GitHub App credentials — when AppID is non-zero, these override OctoIdentity.
	AppID  int64  `env:"GITHUB_APP_ID"`
	AppKey string `env:"GITHUB_APP_KEY"`
}{})

// changedFilesHist counts files changed per push, by resolving source.
var changedFilesHist = promauto.NewHistogramVec(
	prometheus.HistogramOpts{
		Name:    "github_path_reconciler_push_changed_files",
		Help:    "Number of files a push changed, by the source that resolved them.",
		Buckets: []float64{1, 2, 5, 10, 20, 50, 100, 300, 1000},
	},
	[]string{"method"},
)

// pushCommitsHist gauges commits per push (how often the single-commit case occurs).
var pushCommitsHist = promauto.NewHistogram(prometheus.HistogramOpts{
	Name:    "github_path_reconciler_push_commits",
	Help:    "Number of commits per push.",
	Buckets: []float64{1, 2, 3, 5, 10, 25, 50, 100},
})

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	go httpmetrics.ServeMetrics()
	defer httpmetrics.SetupTracer(ctx)()

	// Parse repos config and build lookup map keyed by "owner/repo"
	repoConfigs, err := patterns.ParseRepoConfigs(env.ReposConfig)
	if err != nil {
		clog.FatalContextf(ctx, "Failed to parse repos config: %v", err)
	}
	repoMap := make(map[string]patterns.RepoConfig, len(repoConfigs))
	for _, cfg := range repoConfigs {
		repoMap[cfg.Owner+"/"+cfg.Repo] = cfg
	}

	// Set up workqueue client
	wqClient, err := workqueue.NewWorkqueueClient(ctx, env.WorkqueueAddr)
	if err != nil {
		clog.FatalContextf(ctx, "Failed to create workqueue client: %v", err)
	}
	defer wqClient.Close()

	clientCache, err := buildClientCache(ctx)
	if err != nil {
		clog.FatalContextf(ctx, "Failed to create GitHub client cache: %v", err)
	}

	handler := &pushHandler{
		clientCache: clientCache,
		identity:    env.Identity,
		wqClient:    wqClient,
		repoMap:     repoMap,
	}

	// Set up Cloud Events receiver
	ceClient, err := cloudevents.NewClientHTTP(cloudevents.WithPort(env.Port))
	if err != nil {
		clog.FatalContextf(ctx, "Failed to create CloudEvents client: %v", err)
	}

	clog.InfoContextf(ctx, "Starting push listener on port %d", env.Port)
	if err := ceClient.StartReceiver(ctx, handler.handlePushEvent); err != nil {
		clog.FatalContextf(ctx, "Failed to start receiver: %v", err)
	}
}

// fetchRepoConfig fetches .{identity}.yaml from the repo at the given ref.
// Returns (config, true, nil) if found, (zero, false, nil) if absent, or an error.
func (h *pushHandler) fetchRepoConfig(ctx context.Context, owner, repo, ref string) (patterns.RepoConfig, bool, error) {
	if h.identity == "" {
		return patterns.RepoConfig{}, false, nil
	}

	ghClient, err := h.clientCache.Get(ctx, owner, repo)
	if err != nil {
		return patterns.RepoConfig{}, false, err
	}

	filename := "." + h.identity + ".yaml"
	file, _, resp, err := ghClient.Repositories.GetContents(ctx, owner, repo, filename,
		&github.RepositoryContentGetOptions{Ref: ref})
	if err != nil {
		if resp != nil && resp.StatusCode == http.StatusNotFound {
			return patterns.RepoConfig{}, false, nil
		}
		return patterns.RepoConfig{}, false, fmt.Errorf("fetch %s from %s/%s@%s: %w", filename, owner, repo, ref, err)
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

func buildClientCache(ctx context.Context) (*githubreconciler.ClientCache, error) {
	if env.AppID != 0 {
		app, err := githubreconciler.NewApp(ctx, env.AppID, env.AppKey)
		if err != nil {
			return nil, err
		}
		return githubreconciler.NewClientCache(app.TokenSourceFunc()), nil
	}
	return githubreconciler.NewClientCache(func(ctx context.Context, org, repo string) (oauth2.TokenSource, error) {
		return githubreconciler.NewRepoTokenSource(ctx, env.Identity, org, repo), nil
	}), nil
}

type pushHandler struct {
	clientCache *githubreconciler.ClientCache
	identity    string
	wqClient    workqueue.Client
	repoMap     map[string]patterns.RepoConfig
}

func (h *pushHandler) handlePushEvent(ctx context.Context, event cloudevents.Event) error {
	clog.InfoContextf(ctx, "Received event: type=%s, source=%s, subject=%s", event.Type(), event.Source(), event.Subject())

	if event.Type() != "dev.chainguard.github.push" {
		clog.InfoContextf(ctx, "Ignoring non-push event: %s", event.Type())
		return nil
	}

	// Unwrap the event envelope - the trampoline wraps the GitHub payload
	var envelope struct {
		Body github.PushEvent `json:"body"`
	}
	if err := event.DataAs(&envelope); err != nil {
		return fmt.Errorf("failed to parse event envelope: %w", err)
	}

	pushEvent := envelope.Body
	owner := pushEvent.GetRepo().GetOwner().GetLogin()
	repo := pushEvent.GetRepo().GetName()
	ref := pushEvent.GetRef()
	before := pushEvent.GetBefore()
	after := pushEvent.GetAfter()
	defaultBranch := pushEvent.GetRepo().GetDefaultBranch()

	ctx = clog.WithValues(ctx,
		"owner", owner,
		"repo", repo,
		"ref", ref,
		"before", before,
		"after", after,
		"default_branch", defaultBranch,
	)

	// Look up the explicit repo config. If missing, try to fetch it from
	// .{identity}.yaml at the pushed commit; skip if the file doesn't exist.
	cfg, ok := h.repoMap[owner+"/"+repo]
	if !ok {
		var err error
		cfg, ok, err = h.fetchRepoConfig(ctx, owner, repo, after)
		if err != nil {
			return fmt.Errorf("fetch repo config for %s/%s: %w", owner, repo, err)
		}
		if !ok {
			clog.InfoContextf(ctx, "No config for %s/%s, skipping", owner, repo)
			return nil
		}
	}

	// Extract branch name from ref (refs/heads/main -> main)
	branch := strings.TrimPrefix(ref, "refs/heads/")

	// Only process pushes to the default branch
	if branch != defaultBranch {
		clog.InfoContextf(ctx, "Ignoring push to non-default branch %q (default is %q)", branch, defaultBranch)
		return nil
	}

	clog.InfoContextf(ctx, "Processing push event on default branch %q", defaultBranch)

	changedFiles, method, err := h.resolveChangedFiles(ctx, &pushEvent, owner, repo, before, after)
	if err != nil {
		return err
	}
	changedFilesHist.WithLabelValues(method).Observe(float64(len(changedFiles)))
	pushCommitsHist.Observe(float64(len(pushEvent.Commits)))

	clog.InfoContextf(ctx, "Processing %d changed files", len(changedFiles))

	// Match changed files against this repo's patterns
	keySet := make(map[string]struct{})
	for file := range changedFiles {
		if key := cfg.MatchPath(file); key != "" {
			url := fmt.Sprintf("https://github.com/%s/%s/blob/%s/%s", owner, repo, defaultBranch, key)
			keySet[url] = struct{}{}
		}
	}

	clog.InfoContextf(ctx, "Enqueueing %d unique keys", len(keySet))

	eg, egCtx := errgroup.WithContext(ctx)
	for url := range keySet {
		eg.Go(func() error {
			_, err := h.wqClient.Process(egCtx, &workqueue.ProcessRequest{
				Key:      url,
				Priority: 100, // Process push events immediately
			})
			if err != nil {
				clog.ErrorContextf(egCtx, "Failed to process key %q: %v", url, err)
				return err
			}
			clog.InfoContextf(egCtx, "Enqueued %q", url)
			return nil
		})
	}

	if err := eg.Wait(); err != nil {
		return fmt.Errorf("failed to enqueue all keys: %w", err)
	}

	return nil
}

// compareFilesCap is the max files Compare returns. At the cap it's truncated and
// we fall back to the tree. https://docs.github.com/en/rest/commits/commits#compare-two-commits
const compareFilesCap = 300

// resolveChangedFiles returns the set of file paths the push changed, a label
// naming the source that resolved them (payload, compare, or tree), and an error.
// It uses the cheapest trustworthy source: the payload for a single-commit
// ancestor push (no API calls, exact), else Compare for any ancestor push (one
// call), else a recursive tree diff. Forced/create/delete and a truncated Compare
// fall to the tree.
func (h *pushHandler) resolveChangedFiles(ctx context.Context, pe *github.PushEvent, owner, repo, before, after string) (map[string]struct{}, string, error) {
	// Forced pushes and branch create/delete aren't an ancestor range, where the
	// payload and Compare's merge-base diff could miss changes - use only the tree.
	ancestorRange := !pe.GetForced() && !pe.GetCreated() && !pe.GetDeleted()

	// A single commit on an ancestor range has no merge-from-main or
	// revert-within-push churn, so its payload is exactly the net diff.
	if ancestorRange && len(pe.Commits) == 1 {
		return changedPathsFromPayload(pe), "payload", nil
	}

	gh, err := h.clientCache.Get(ctx, owner, repo)
	if err != nil {
		return nil, "", fmt.Errorf("failed to get GitHub client: %w", err)
	}

	if ancestorRange {
		cmpFiles, complete, err := changedPathsFromCompare(ctx, gh, owner, repo, before, after)
		if err != nil {
			return nil, "", err
		}
		if complete {
			return cmpFiles, "compare", nil
		}
	}

	treeFiles, err := changedPathsFromTree(ctx, gh, owner, repo, before, after)
	if err != nil {
		return nil, "", err
	}
	return treeFiles, "tree", nil
}

// changedPathsFromPayload returns the union of the files the push's commits
// touched per the webhook payload (no API calls). The caller must confirm the
// push is trustworthy (a single commit on an ancestor range) before using it.
func changedPathsFromPayload(pe *github.PushEvent) map[string]struct{} {
	changed := make(map[string]struct{})
	for _, c := range pe.Commits {
		if c == nil {
			continue
		}
		for _, f := range c.Added {
			changed[f] = struct{}{}
		}
		for _, f := range c.Modified {
			changed[f] = struct{}{}
		}
		for _, f := range c.Removed {
			changed[f] = struct{}{}
		}
	}
	return changed
}

// changedPathsFromCompare lists before→after changed files in one Compare call.
// At compareFilesCap the list is truncated, so it returns (nil, false) and the
// caller uses the tree. Renames carry both Filename and PreviousFilename.
func changedPathsFromCompare(ctx context.Context, gh *github.Client, owner, repo, before, after string) (map[string]struct{}, bool, error) {
	cmp, _, err := gh.Repositories.CompareCommits(ctx, owner, repo, before, after, nil)
	if err != nil {
		return nil, false, fmt.Errorf("failed to compare %s...%s: %w", before, after, err)
	}

	// Truncated: the caller falls back to the tree, so don't build the set.
	if len(cmp.Files) >= compareFilesCap {
		return nil, false, nil
	}

	changed := make(map[string]struct{}, len(cmp.Files))
	for _, f := range cmp.Files {
		changed[f.GetFilename()] = struct{}{}
		if prev := f.GetPreviousFilename(); prev != "" {
			changed[prev] = struct{}{}
		}
	}
	return changed, true, nil
}

// changedPathsFromTree diffs the full recursive before/after trees - four API
// calls, the fallback when payload and Compare don't apply. Warns on truncation.
func changedPathsFromTree(ctx context.Context, gh *github.Client, owner, repo, before, after string) (map[string]struct{}, error) {
	beforeCommit, _, err := gh.Git.GetCommit(ctx, owner, repo, before)
	if err != nil {
		return nil, fmt.Errorf("failed to get before commit: %w", err)
	}
	afterCommit, _, err := gh.Git.GetCommit(ctx, owner, repo, after)
	if err != nil {
		return nil, fmt.Errorf("failed to get after commit: %w", err)
	}

	beforeTree, _, err := gh.Git.GetTree(ctx, owner, repo, beforeCommit.Tree.GetSHA(), true)
	if err != nil {
		return nil, fmt.Errorf("failed to get before tree: %w", err)
	}
	afterTree, _, err := gh.Git.GetTree(ctx, owner, repo, afterCommit.Tree.GetSHA(), true)
	if err != nil {
		return nil, fmt.Errorf("failed to get after tree: %w", err)
	}
	if beforeTree.GetTruncated() || afterTree.GetTruncated() {
		clog.WarnContextf(ctx, "recursive tree for %s/%s was truncated, changed-file detection may be incomplete", owner, repo)
	}

	// Build maps of file paths to their blob SHAs
	beforeFiles := make(map[string]string, len(beforeTree.Entries))
	for _, entry := range beforeTree.Entries {
		if entry.GetType() == "blob" {
			beforeFiles[entry.GetPath()] = entry.GetSHA()
		}
	}
	afterFiles := make(map[string]string, len(afterTree.Entries))
	for _, entry := range afterTree.Entries {
		if entry.GetType() == "blob" {
			afterFiles[entry.GetPath()] = entry.GetSHA()
		}
	}

	// Find all changed files (added, modified, or deleted)
	changed := make(map[string]struct{})
	for path, afterSHA := range afterFiles {
		if beforeSHA, exists := beforeFiles[path]; !exists || beforeSHA != afterSHA {
			changed[path] = struct{}{}
		}
	}
	for path := range beforeFiles {
		if _, exists := afterFiles[path]; !exists {
			changed[path] = struct{}{}
		}
	}
	return changed, nil
}
