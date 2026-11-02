/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package patterns_test

import (
	"fmt"

	"chainguard.dev/terraform-infra-reconcilers/modules/github-path-reconciler/internal/patterns"
)

func ExampleParseRepoConfigs() {
	const configJSON = `[
		{"owner":"chainguard-dev","repo":"wolfi-os","path_patterns":["(packages/.+\\.yaml)"],"resync_period_hours":24},
		{"owner":"chainguard-images","repo":"images","path_patterns":["(images/[^/]+/.+)"],"resync_period_hours":168}
	]`

	configs, err := patterns.ParseRepoConfigs(configJSON)
	if err != nil {
		fmt.Println("error:", err)
		return
	}

	for _, cfg := range configs {
		fmt.Printf("repo: %s/%s, period: %v\n", cfg.Owner, cfg.Repo, cfg.Period)
	}
	// Output:
	// repo: chainguard-dev/wolfi-os, period: 24h0m0s
	// repo: chainguard-images/images, period: 168h0m0s
}

func ExampleParseRepoConfigFile() {
	content := []byte(`
path_patterns:
  - "(modules/.+\\.tf)"
  - "(scripts/.+)"
resync_period_hours: 24
`)

	cfg, err := patterns.ParseRepoConfigFile(content, "chainguard-dev", "mono")
	if err != nil {
		fmt.Println("error:", err)
		return
	}

	for _, p := range []string{"modules/vpc.tf", "scripts/deploy.sh", "README.md"} {
		key, ok := cfg.Matcher.Match(p)
		fmt.Printf("%s/%s %q -> %q, %t\n", cfg.Owner, cfg.Repo, p, key, ok)
	}
	// Output:
	// chainguard-dev/mono "modules/vpc.tf" -> "modules/vpc.tf", true
	// chainguard-dev/mono "scripts/deploy.sh" -> "scripts/deploy.sh", true
	// chainguard-dev/mono "README.md" -> "", false
}
