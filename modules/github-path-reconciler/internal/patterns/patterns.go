/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package patterns

import (
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"chainguard.dev/driftlessaf/reconcilers/pathpatterns"
	"gopkg.in/yaml.v3"
)

// RepoConfig holds the compiled path patterns for a single repository.
type RepoConfig struct {
	Owner   string
	Repo    string
	Matcher *pathpatterns.Matcher
	// Period is the per-repo resync period. Required; every repo declares
	// its own value either in its REPOS_CONFIG entry or in .{identity}.yaml.
	Period time.Duration
}

// repoConfigJSON is the JSON wire format for a single repo entry in REPOS_CONFIG.
type repoConfigJSON struct {
	Owner             string   `json:"owner"`
	Repo              string   `json:"repo"`
	PathPatterns      []string `json:"path_patterns"`
	ExcludePatterns   []string `json:"exclude_patterns,omitempty"`
	ResyncPeriodHours int      `json:"resync_period_hours"`
}

// ParseRepoConfigs parses a JSON array of repo config objects (the REPOS_CONFIG env var)
// and compiles the path_patterns for each entry.
func ParseRepoConfigs(configStr string) ([]RepoConfig, error) {
	var raw []repoConfigJSON
	if err := json.Unmarshal([]byte(configStr), &raw); err != nil {
		return nil, fmt.Errorf("failed to parse repos config JSON: %w", err)
	}
	configs := make([]RepoConfig, 0, len(raw))
	for _, r := range raw {
		if r.Owner == "" {
			return nil, errors.New("repo entry missing owner")
		}
		if r.Repo == "" {
			return nil, errors.New("repo entry missing repo")
		}
		if len(r.PathPatterns) == 0 {
			return nil, fmt.Errorf("repo %s/%s: no valid patterns found", r.Owner, r.Repo)
		}
		matcher, err := pathpatterns.New(r.PathPatterns, r.ExcludePatterns)
		if err != nil {
			return nil, fmt.Errorf("repo %s/%s: %w", r.Owner, r.Repo, err)
		}
		period, err := periodFromHours(r.ResyncPeriodHours)
		if err != nil {
			return nil, fmt.Errorf("repo %s/%s: %w", r.Owner, r.Repo, err)
		}
		configs = append(configs, RepoConfig{
			Owner:   r.Owner,
			Repo:    r.Repo,
			Matcher: matcher,
			Period:  period,
		})
	}
	return configs, nil
}

// repoConfigFile is the YAML format of the per-repo config file
// (e.g. .skillup.yaml or .moore-door.yaml).
type repoConfigFile struct {
	PathPatterns      []string `yaml:"path_patterns"`
	ExcludePatterns   []string `yaml:"exclude_patterns"`
	ResyncPeriodHours int      `yaml:"resync_period_hours"`
}

// ParseRepoConfigFile parses the content of a .{identity}.yaml repo config
// file and returns a RepoConfig for the given owner/repo. Returns an error if
// the file is missing required fields or contains invalid patterns.
func ParseRepoConfigFile(content []byte, owner, repo string) (RepoConfig, error) {
	var raw repoConfigFile
	if err := yaml.Unmarshal(content, &raw); err != nil {
		return RepoConfig{}, fmt.Errorf("parse repo config file for %s/%s: %w", owner, repo, err)
	}
	if len(raw.PathPatterns) == 0 {
		return RepoConfig{}, fmt.Errorf("repo config file for %s/%s has no path_patterns", owner, repo)
	}
	matcher, err := pathpatterns.New(raw.PathPatterns, raw.ExcludePatterns)
	if err != nil {
		return RepoConfig{}, fmt.Errorf("%s/%s: %w", owner, repo, err)
	}
	period, err := periodFromHours(raw.ResyncPeriodHours)
	if err != nil {
		return RepoConfig{}, fmt.Errorf("%s/%s: %w", owner, repo, err)
	}
	return RepoConfig{Owner: owner, Repo: repo, Matcher: matcher, Period: period}, nil
}

// periodFromHours converts a positive hour count to a Duration. Zero or
// negative is rejected — every repo must declare a resync period.
func periodFromHours(hours int) (time.Duration, error) {
	if hours <= 0 {
		return 0, fmt.Errorf("resync_period_hours must be positive, got %d", hours)
	}
	return time.Duration(hours) * time.Hour, nil
}
