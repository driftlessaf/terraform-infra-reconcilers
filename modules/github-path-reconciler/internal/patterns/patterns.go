/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package patterns

import (
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"time"

	"gopkg.in/yaml.v3"
)

// RepoConfig holds the compiled path patterns for a single repository.
type RepoConfig struct {
	Owner           string
	Repo            string
	Patterns        []*regexp.Regexp
	ExcludePatterns []*regexp.Regexp
	// Period is the per-repo resync period. Required; every repo declares
	// its own value either in its REPOS_CONFIG entry or in .{identity}.yaml.
	Period time.Duration
}

// MatchPath returns the first captured key from path, or "" if the path is
// excluded or no include pattern matches.
func (r *RepoConfig) MatchPath(path string) string {
	for _, re := range r.ExcludePatterns {
		if re.MatchString(path) {
			return ""
		}
	}
	for _, re := range r.Patterns {
		if m := re.FindStringSubmatch(path); len(m) > 1 {
			return m[1]
		}
	}
	return ""
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
		pats, err := compilePatterns(r.PathPatterns)
		if err != nil {
			return nil, fmt.Errorf("repo %s/%s: %w", r.Owner, r.Repo, err)
		}
		excludePats, err := compileMatchPatterns(r.ExcludePatterns)
		if err != nil {
			return nil, fmt.Errorf("repo %s/%s exclude_patterns: %w", r.Owner, r.Repo, err)
		}
		period, err := periodFromHours(r.ResyncPeriodHours)
		if err != nil {
			return nil, fmt.Errorf("repo %s/%s: %w", r.Owner, r.Repo, err)
		}
		configs = append(configs, RepoConfig{
			Owner:           r.Owner,
			Repo:            r.Repo,
			Patterns:        pats,
			ExcludePatterns: excludePats,
			Period:          period,
		})
	}
	return configs, nil
}

// Parse parses a JSON array of regex patterns and validates that each has exactly one capture group.
func Parse(patternsStr string) ([]*regexp.Regexp, error) {
	var patternStrings []string
	if err := json.Unmarshal([]byte(patternsStr), &patternStrings); err != nil {
		return nil, fmt.Errorf("failed to parse patterns JSON: %w", err)
	}
	if len(patternStrings) == 0 {
		return nil, errors.New("no valid patterns found")
	}
	return compilePatterns(patternStrings)
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
	pats, err := compilePatterns(raw.PathPatterns)
	if err != nil {
		return RepoConfig{}, fmt.Errorf("%s/%s: %w", owner, repo, err)
	}
	excludePats, err := compileMatchPatterns(raw.ExcludePatterns)
	if err != nil {
		return RepoConfig{}, fmt.Errorf("%s/%s exclude_patterns: %w", owner, repo, err)
	}
	period, err := periodFromHours(raw.ResyncPeriodHours)
	if err != nil {
		return RepoConfig{}, fmt.Errorf("%s/%s: %w", owner, repo, err)
	}
	return RepoConfig{Owner: owner, Repo: repo, Patterns: pats, ExcludePatterns: excludePats, Period: period}, nil
}

// periodFromHours converts a positive hour count to a Duration. Zero or
// negative is rejected — every repo must declare a resync period.
func periodFromHours(hours int) (time.Duration, error) {
	if hours <= 0 {
		return 0, fmt.Errorf("resync_period_hours must be positive, got %d", hours)
	}
	return time.Duration(hours) * time.Hour, nil
}

func compilePatterns(patternStrings []string) ([]*regexp.Regexp, error) {
	compiled := make([]*regexp.Regexp, 0, len(patternStrings))
	for _, patternStr := range patternStrings {
		// Add implicit ^ and $ anchors unconditionally
		anchored := "^" + patternStr + "$"

		regex, err := regexp.Compile(anchored)
		if err != nil {
			return nil, fmt.Errorf("invalid regex %q: %w", anchored, err)
		}

		// Ensure it has exactly one capture group
		if numCaptures := regex.NumSubexp(); numCaptures != 1 {
			return nil, fmt.Errorf("regex %q must have exactly one capture group, got %d", anchored, numCaptures)
		}

		compiled = append(compiled, regex)
	}
	return compiled, nil
}

// compileMatchPatterns compiles patterns for match-only use (no capture group required).
// Returns nil for an empty slice since exclude patterns are optional.
func compileMatchPatterns(patternStrings []string) ([]*regexp.Regexp, error) {
	if len(patternStrings) == 0 {
		return nil, nil
	}
	compiled := make([]*regexp.Regexp, 0, len(patternStrings))
	for _, patternStr := range patternStrings {
		anchored := "^" + patternStr + "$"
		regex, err := regexp.Compile(anchored)
		if err != nil {
			return nil, fmt.Errorf("invalid regex %q: %w", anchored, err)
		}
		compiled = append(compiled, regex)
	}
	return compiled, nil
}
