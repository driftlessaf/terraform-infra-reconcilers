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
