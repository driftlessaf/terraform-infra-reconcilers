/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package patterns

import (
	"strings"
	"testing"
)

func TestParse(t *testing.T) {
	tests := []struct {
		name        string
		input       string
		wantErr     bool
		errContains string
		// For success cases, test that specific paths match/don't match
		matchPaths   []string
		noMatchPaths []string
	}{{
		name:  "single pattern matches all files",
		input: `["(.+)"]`,
		matchPaths: []string{
			"file.txt",
			"dir/file.yaml",
			"deep/nested/path/file.go",
		},
		noMatchPaths: []string{
			"",
		},
	}, {
		name:  "pattern matches yaml files only",
		input: `["(.+\\.yaml)"]`,
		matchPaths: []string{
			"config.yaml",
			"dir/config.yaml",
			"deep/nested/file.yaml",
		},
		noMatchPaths: []string{
			"file.txt",
			"file.yml",
			"yaml",
		},
	}, {
		name:  "pattern matches specific directory",
		input: `["(infrastructure/.+)"]`,
		matchPaths: []string{
			"infrastructure/main.tf",
			"infrastructure/nested/file.go",
		},
		noMatchPaths: []string{
			"main.tf",
			"src/infrastructure/main.tf",
			"infrastructure",
		},
	}, {
		name:  "multiple patterns",
		input: `["(.+\\.yaml)", "(configs/.+)"]`,
		matchPaths: []string{
			"file.yaml",
			"dir/file.yaml",
			"configs/app.json",
			"configs/nested/config.toml",
		},
		noMatchPaths: []string{
			"file.txt",
			"other/file.txt",
		},
	}, {
		name:        "invalid JSON",
		input:       `not json`,
		wantErr:     true,
		errContains: "failed to parse patterns JSON",
	}, {
		name:        "empty array",
		input:       `[]`,
		wantErr:     true,
		errContains: "no valid patterns found",
	}, {
		name:        "pattern with no capture group",
		input:       `[".+\\.yaml"]`,
		wantErr:     true,
		errContains: "must have exactly one capture group, got 0",
	}, {
		name:        "pattern with multiple capture groups",
		input:       `["(.+)/(.+)"]`,
		wantErr:     true,
		errContains: "must have exactly one capture group, got 2",
	}, {
		name:        "invalid regex",
		input:       `["(invalid["]`,
		wantErr:     true,
		errContains: "invalid regex",
	}, {
		name:  "pattern without explicit anchors gets them added",
		input: `["(test.*)"]`,
		matchPaths: []string{
			"test",
			"test123",
			"testing",
			"test-suffix-extra",
		},
		noMatchPaths: []string{
			"prefix-test",
		},
	}, {
		name:  "pattern extracts correct capture group",
		input: `["dir/(.+\\.go)"]`,
		matchPaths: []string{
			"dir/main.go",
			"dir/test.go",
			"dir/nested/main.go",
		},
		noMatchPaths: []string{
			"main.go",
			"other/main.go",
		},
	}}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			patterns, err := Parse(tt.input)

			if tt.wantErr {
				if err == nil {
					t.Fatal("Parse() expected error, got nil")
				}
				if tt.errContains != "" {
					if got := err.Error(); !strings.Contains(got, tt.errContains) {
						t.Errorf("Parse() error: got = %q, wanted to contain = %q", got, tt.errContains)
					}
				}
				return
			}

			if err != nil {
				t.Fatalf("Parse() unexpected error: %v", err)
			}

			if len(patterns) == 0 {
				t.Fatal("Parse() returned empty patterns slice")
			}

			// Test that expected paths match
			for _, path := range tt.matchPaths {
				matched := false
				for _, pattern := range patterns {
					if pattern.MatchString(path) {
						matched = true
						break
					}
				}
				if !matched {
					t.Errorf("expected path %q to match one of the patterns, but it didn't", path)
				}
			}

			// Test that unexpected paths don't match
			for _, path := range tt.noMatchPaths {
				for i, pattern := range patterns {
					if pattern.MatchString(path) {
						t.Errorf("expected path %q not to match pattern[%d] %q, but it did", path, i, pattern.String())
					}
				}
			}
		})
	}
}

func TestParseCaptureGroup(t *testing.T) {
	tests := []struct {
		name         string
		input        string
		testPath     string
		wantCaptured string
	}{{
		name:         "captures entire path",
		input:        `["(.+)"]`,
		testPath:     "dir/file.txt",
		wantCaptured: "dir/file.txt",
	}, {
		name:         "captures filename only",
		input:        `[".+/([^/]+)"]`,
		testPath:     "dir/file.txt",
		wantCaptured: "file.txt",
	}, {
		name:         "captures yaml files",
		input:        `["(.+\\.yaml)"]`,
		testPath:     "config/app.yaml",
		wantCaptured: "config/app.yaml",
	}, {
		name:         "captures path within directory",
		input:        `["infrastructure/(.+)"]`,
		testPath:     "infrastructure/modules/vpc.tf",
		wantCaptured: "modules/vpc.tf",
	}}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			patterns, err := Parse(tt.input)
			if err != nil {
				t.Fatalf("Parse() unexpected error: %v", err)
			}

			if len(patterns) == 0 {
				t.Fatal("Parse() returned empty patterns slice")
			}

			matches := patterns[0].FindStringSubmatch(tt.testPath)
			if len(matches) < 2 {
				t.Fatalf("pattern did not match path %q", tt.testPath)
			}

			captured := matches[1]
			if captured != tt.wantCaptured {
				t.Errorf("captured group: got = %q, wanted = %q", captured, tt.wantCaptured)
			}
		})
	}
}

func TestParseRepoConfigs(t *testing.T) {
	tests := []struct {
		name        string
		input       string
		wantErr     bool
		errContains string
		wantOwners  []string
		wantRepos   []string
	}{{
		name:       "empty array",
		input:      `[]`,
		wantOwners: []string{},
		wantRepos:  []string{},
	}, {
		name:        "invalid JSON",
		input:       `not json`,
		wantErr:     true,
		errContains: "failed to parse repos config JSON",
	}, {
		name:        "missing owner",
		input:       `[{"repo":"wolfi-os","path_patterns":["(.+)"]}]`,
		wantErr:     true,
		errContains: "missing owner",
	}, {
		name:        "missing repo",
		input:       `[{"owner":"chainguard-dev","path_patterns":["(.+)"]}]`,
		wantErr:     true,
		errContains: "missing repo",
	}, {
		name:        "empty path_patterns",
		input:       `[{"owner":"chainguard-dev","repo":"wolfi-os","path_patterns":[]}]`,
		wantErr:     true,
		errContains: "no valid patterns found",
	}, {
		name:        "invalid pattern in repo",
		input:       `[{"owner":"chainguard-dev","repo":"wolfi-os","path_patterns":["(invalid["]}]`,
		wantErr:     true,
		errContains: "chainguard-dev/wolfi-os",
	}, {
		name:       "single repo",
		input:      `[{"owner":"chainguard-dev","repo":"wolfi-os","path_patterns":["(packages/.+\\.yaml)"]}]`,
		wantOwners: []string{"chainguard-dev"},
		wantRepos:  []string{"wolfi-os"},
	}, {
		name:       "multiple repos",
		input:      `[{"owner":"chainguard-dev","repo":"wolfi-os","path_patterns":["(packages/.+\\.yaml)"]},{"owner":"chainguard-images","repo":"images-private","path_patterns":["(images/[^/]+)/.*"]}]`,
		wantOwners: []string{"chainguard-dev", "chainguard-images"},
		wantRepos:  []string{"wolfi-os", "images-private"},
	}}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			configs, err := ParseRepoConfigs(tt.input)
			if tt.wantErr {
				if err == nil {
					t.Fatal("ParseRepoConfigs() expected error, got nil")
				}
				if tt.errContains != "" {
					if got := err.Error(); !strings.Contains(got, tt.errContains) {
						t.Errorf("ParseRepoConfigs() error: got = %q, wanted to contain = %q", got, tt.errContains)
					}
				}
				return
			}
			if err != nil {
				t.Fatalf("ParseRepoConfigs() unexpected error: %v", err)
			}
			if len(configs) != len(tt.wantOwners) {
				t.Fatalf("ParseRepoConfigs() len: got = %d, wanted = %d", len(configs), len(tt.wantOwners))
			}
			for i, cfg := range configs {
				if cfg.Owner != tt.wantOwners[i] {
					t.Errorf("configs[%d].Owner: got = %q, wanted = %q", i, cfg.Owner, tt.wantOwners[i])
				}
				if cfg.Repo != tt.wantRepos[i] {
					t.Errorf("configs[%d].Repo: got = %q, wanted = %q", i, cfg.Repo, tt.wantRepos[i])
				}
				if len(cfg.Patterns) == 0 {
					t.Errorf("configs[%d].Patterns: got empty, wanted non-empty", i)
				}
			}
		})
	}
}

func TestRepoConfigMatchPath(t *testing.T) {
	configs, err := ParseRepoConfigs(`[{"owner":"chainguard-dev","repo":"wolfi-os","path_patterns":["(packages/.+\\.yaml)"]}]`)
	if err != nil {
		t.Fatalf("ParseRepoConfigs() unexpected error: %v", err)
	}
	cfg := configs[0]

	tests := []struct {
		path string
		want string
	}{{
		path: "packages/foo.yaml",
		want: "packages/foo.yaml",
	}, {
		path: "packages/nested/bar.yaml",
		want: "packages/nested/bar.yaml",
	}, {
		path: "other/foo.go",
		want: "",
	}, {
		path: "packages/foo.go",
		want: "",
	}}

	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			got := cfg.MatchPath(tt.path)
			if got != tt.want {
				t.Errorf("MatchPath(%q): got = %q, wanted = %q", tt.path, got, tt.want)
			}
		})
	}
}

func TestParseAnchoring(t *testing.T) {
	// Test that anchors are always added unconditionally
	input := `["(.+\\.yaml)"]`
	patterns, err := Parse(input)
	if err != nil {
		t.Fatalf("Parse() unexpected error: %v", err)
	}

	pattern := patterns[0].String()

	// Check that the compiled pattern has anchors
	if pattern[0] != '^' {
		t.Errorf("pattern should start with ^, got: %s", pattern)
	}
	if pattern[len(pattern)-1] != '$' {
		t.Errorf("pattern should end with $, got: %s", pattern)
	}

	// Verify it matches complete paths with .yaml extension
	testCases := []struct {
		path        string
		shouldMatch bool
	}{
		{"file.yaml", true},
		{"dir/file.yaml", true},
		{"prefix-file.yaml", true},
		{"file.yaml-extra", false},
		{"file.txt", false},
	}

	for _, tc := range testCases {
		matched := patterns[0].MatchString(tc.path)
		if matched != tc.shouldMatch {
			t.Errorf("path %q: got match = %v, wanted = %v", tc.path, matched, tc.shouldMatch)
		}
	}
}
