/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

// Package patterns parses the path-reconciler configuration for each
// repository, from the REPOS_CONFIG environment variable (ParseRepoConfigs)
// or from a .{identity}.yaml file in the repository (ParseRepoConfigFile).
// The path patterns compile to a pathpatterns.Matcher.
package patterns
