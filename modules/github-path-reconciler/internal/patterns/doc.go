/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

// Package patterns provides utilities for parsing and validating regex patterns
// used to match GitHub file paths. Each pattern must have exactly one capture
// group, which is used to extract the relevant portion of the matched path.
//
// The primary entry point for multi-repo reconcilers is ParseRepoConfigs, which
// parses the REPOS_CONFIG JSON env var into a slice of RepoConfig values, each
// holding the compiled patterns for a single repository. For legacy single-repo
// use, Parse compiles a JSON array of pattern strings directly.
package patterns
