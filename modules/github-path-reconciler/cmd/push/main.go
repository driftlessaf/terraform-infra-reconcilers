/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"fmt"
	"os/signal"
	"strings"
	"syscall"

	"github.com/chainguard-dev/clog"
	_ "github.com/chainguard-dev/clog/gcp/init"
	cloudevents "github.com/cloudevents/sdk-go/v2"
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
	Port int `env:"PORT,default=8080"`

	// Workqueue configuration
	WorkqueueAddr string `env:"WORKQUEUE_ADDR,required"`

	// Repos config (JSON array of {owner, repo, path_patterns})
	ReposConfig string `env:"REPOS_CONFIG,required"`

	// Octo STS identity
	OctoIdentity string `env:"OCTO_IDENTITY,required"`
}{})

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

	clientCache := githubreconciler.NewClientCache(func(ctx context.Context, org, repo string) (oauth2.TokenSource, error) {
		return githubreconciler.NewRepoTokenSource(ctx, env.OctoIdentity, org, repo), nil
	})

	handler := &pushHandler{
		clientCache: clientCache,
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

type pushHandler struct {
	clientCache *githubreconciler.ClientCache
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

	// Look up the repo config; ignore events from repos we don't watch
	cfg, ok := h.repoMap[owner+"/"+repo]
	if !ok {
		clog.InfoContextf(ctx, "Ignoring push event for unwatched repo %s/%s", owner, repo)
		return nil
	}

	// Extract branch name from ref (refs/heads/main -> main)
	branch := strings.TrimPrefix(ref, "refs/heads/")

	// Only process pushes to the default branch
	if branch != defaultBranch {
		clog.InfoContextf(ctx, "Ignoring push to non-default branch %q (default is %q)", branch, defaultBranch)
		return nil
	}

	clog.InfoContextf(ctx, "Processing push event on default branch %q", defaultBranch)

	// Get GitHub client
	ghClient, err := h.clientCache.Get(ctx, owner, repo)
	if err != nil {
		return fmt.Errorf("failed to get GitHub client: %w", err)
	}

	// Use Git Tree comparison to get all changed files.
	// CompareCommits is limited to 300 files, but GetTree has no such limit.
	beforeCommit, _, err := ghClient.Git.GetCommit(ctx, owner, repo, before)
	if err != nil {
		return fmt.Errorf("failed to get before commit: %w", err)
	}

	afterCommit, _, err := ghClient.Git.GetCommit(ctx, owner, repo, after)
	if err != nil {
		return fmt.Errorf("failed to get after commit: %w", err)
	}

	// Get recursive trees for both commits
	beforeTree, _, err := ghClient.Git.GetTree(ctx, owner, repo, beforeCommit.Tree.GetSHA(), true)
	if err != nil {
		return fmt.Errorf("failed to get before tree: %w", err)
	}

	afterTree, _, err := ghClient.Git.GetTree(ctx, owner, repo, afterCommit.Tree.GetSHA(), true)
	if err != nil {
		return fmt.Errorf("failed to get after tree: %w", err)
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
	changedFiles := make(map[string]struct{})
	for path, afterSHA := range afterFiles {
		if beforeSHA, exists := beforeFiles[path]; !exists || beforeSHA != afterSHA {
			changedFiles[path] = struct{}{}
		}
	}
	for path := range beforeFiles {
		if _, exists := afterFiles[path]; !exists {
			changedFiles[path] = struct{}{}
		}
	}

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
