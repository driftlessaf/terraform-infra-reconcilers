/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package patterns_test

import (
	"fmt"

	"chainguard.dev/terraform-infra-reconcilers/modules/github-path-reconciler/internal/patterns"
)

func ExampleParse() {
	pats, err := patterns.Parse(`["(infrastructure/.+)"]`)
	if err != nil {
		fmt.Println("error:", err)
		return
	}

	paths := []string{
		"infrastructure/main.tf",
		"src/other.go",
	}
	for _, p := range paths {
		for _, re := range pats {
			if m := re.FindStringSubmatch(p); len(m) > 1 {
				fmt.Printf("matched %q -> captured %q\n", p, m[1])
			}
		}
	}
	// Output:
	// matched "infrastructure/main.tf" -> captured "infrastructure/main.tf"
}

func ExampleParseRepoConfigs() {
	const configJSON = `[
		{"owner":"chainguard-dev","repo":"wolfi-os","path_patterns":["(packages/.+\\.yaml)"]},
		{"owner":"chainguard-images","repo":"images","path_patterns":["(images/[^/]+/.+)"]}
	]`

	configs, err := patterns.ParseRepoConfigs(configJSON)
	if err != nil {
		fmt.Println("error:", err)
		return
	}

	for _, cfg := range configs {
		fmt.Printf("repo: %s/%s, patterns: %d\n", cfg.Owner, cfg.Repo, len(cfg.Patterns))
	}
	// Output:
	// repo: chainguard-dev/wolfi-os, patterns: 1
	// repo: chainguard-images/images, patterns: 1
}

func ExampleParseRepoConfigFile() {
	content := []byte(`
path_patterns:
  - "(modules/.+\\.tf)"
  - "(scripts/.+)"
`)

	cfg, err := patterns.ParseRepoConfigFile(content, "chainguard-dev", "mono")
	if err != nil {
		fmt.Println("error:", err)
		return
	}

	fmt.Printf("owner: %s, repo: %s, patterns: %d\n", cfg.Owner, cfg.Repo, len(cfg.Patterns))
	// Output:
	// owner: chainguard-dev, repo: mono, patterns: 2
}

func ExampleRepoConfig_MatchPath() {
	cfg, err := patterns.ParseRepoConfigFile([]byte(`
path_patterns:
  - "(packages/.+\\.yaml)"
`), "chainguard-dev", "wolfi-os")
	if err != nil {
		fmt.Println("error:", err)
		return
	}

	paths := []string{
		"packages/foo.yaml",
		"packages/nested/bar.yaml",
		"other/file.go",
	}
	for _, p := range paths {
		key := cfg.MatchPath(p)
		if key != "" {
			fmt.Printf("matched %q -> key %q\n", p, key)
		} else {
			fmt.Printf("no match for %q\n", p)
		}
	}
	// Output:
	// matched "packages/foo.yaml" -> key "packages/foo.yaml"
	// matched "packages/nested/bar.yaml" -> key "packages/nested/bar.yaml"
	// no match for "other/file.go"
}
