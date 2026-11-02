/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package patterns

import (
	"strings"
	"testing"
	"time"
)

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
		name:        "missing resync_period_hours",
		input:       `[{"owner":"chainguard-dev","repo":"wolfi-os","path_patterns":["(.+)"]}]`,
		wantErr:     true,
		errContains: "must be positive",
	}, {
		name:       "single repo",
		input:      `[{"owner":"chainguard-dev","repo":"wolfi-os","path_patterns":["(packages/.+\\.yaml)"],"resync_period_hours":24}]`,
		wantOwners: []string{"chainguard-dev"},
		wantRepos:  []string{"wolfi-os"},
	}, {
		name:       "multiple repos",
		input:      `[{"owner":"chainguard-dev","repo":"wolfi-os","path_patterns":["(packages/.+\\.yaml)"],"resync_period_hours":24},{"owner":"chainguard-images","repo":"images-private","path_patterns":["(images/[^/]+)/.*"],"resync_period_hours":168}]`,
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
				if cfg.Matcher == nil {
					t.Errorf("configs[%d].Matcher: got nil, wanted non-nil", i)
				}
			}
		})
	}
}

func TestParseRepoConfigsExcludePatterns(t *testing.T) {
	configs, err := ParseRepoConfigs(`[{"owner":"chainguard-dev","repo":"mono","path_patterns":["(.*)/[^/]+"],"exclude_patterns":[".*/testdata/.*"],"resync_period_hours":24}]`)
	if err != nil {
		t.Fatalf("ParseRepoConfigs() unexpected error: %v", err)
	}
	cfg := configs[0]

	tests := []struct {
		path string
		want string
	}{{
		path: "bots/skillup/main.go",
		want: "bots/skillup",
	}, {
		path: "ecosystems/eco-fix-review/testdata/foo/bar.yaml",
		want: "",
	}, {
		path: "pkg/testdata/input.json",
		want: "",
	}, {
		path: "solo-file",
		want: "",
	}}

	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			got, _ := cfg.Matcher.Match(tt.path)
			if got != tt.want {
				t.Errorf("Match(%q): got = %q, wanted = %q", tt.path, got, tt.want)
			}
		})
	}
}

func TestParseRepoConfigsInvalidExcludePattern(t *testing.T) {
	_, err := ParseRepoConfigs(`[{"owner":"chainguard-dev","repo":"mono","path_patterns":["(.*)"],"exclude_patterns":["(invalid["],"resync_period_hours":24}]`)
	if err == nil {
		t.Fatal("ParseRepoConfigs() expected error for invalid exclude pattern, got nil")
	}
	if !strings.Contains(err.Error(), "chainguard-dev/mono: exclude pattern") {
		t.Errorf("error should name the repo and the exclude pattern, got: %v", err)
	}
}

func TestParseRepoConfigsResyncPeriod(t *testing.T) {
	tests := []struct {
		name        string
		input       string
		wantErr     bool
		errContains string
		wantPeriod  time.Duration
	}{{
		name:        "missing period rejected",
		input:       `[{"owner":"o","repo":"r","path_patterns":["(.+)"]}]`,
		wantErr:     true,
		errContains: "must be positive",
	}, {
		name:       "explicit period in hours",
		input:      `[{"owner":"o","repo":"r","path_patterns":["(.+)"],"resync_period_hours":24}]`,
		wantPeriod: 24 * time.Hour,
	}, {
		name:       "small period",
		input:      `[{"owner":"o","repo":"r","path_patterns":["(.+)"],"resync_period_hours":1}]`,
		wantPeriod: time.Hour,
	}, {
		name:        "negative period rejected",
		input:       `[{"owner":"o","repo":"r","path_patterns":["(.+)"],"resync_period_hours":-1}]`,
		wantErr:     true,
		errContains: "must be positive",
	}}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			cfgs, err := ParseRepoConfigs(tc.input)
			if tc.wantErr {
				if err == nil {
					t.Fatal("ParseRepoConfigs: got = nil, want error")
				}
				if tc.errContains != "" && !strings.Contains(err.Error(), tc.errContains) {
					t.Errorf("error: got = %q, want containing %q", err.Error(), tc.errContains)
				}
				return
			}
			if err != nil {
				t.Fatalf("ParseRepoConfigs: unexpected error %v", err)
			}
			if len(cfgs) != 1 {
				t.Fatalf("len(cfgs): got = %d, want 1", len(cfgs))
			}
			if cfgs[0].Period != tc.wantPeriod {
				t.Errorf("Period: got = %v, want %v", cfgs[0].Period, tc.wantPeriod)
			}
		})
	}
}

func TestParseRepoConfigFileResyncPeriod(t *testing.T) {
	tests := []struct {
		name       string
		content    string
		wantPeriod time.Duration
		wantErr    bool
	}{{
		name: "missing period rejected",
		content: `path_patterns:
  - "(.+)"`,
		wantErr: true,
	}, {
		name: "explicit period",
		content: `path_patterns:
  - "(.+)"
resync_period_hours: 168`,
		wantPeriod: 168 * time.Hour,
	}, {
		name: "negative period",
		content: `path_patterns:
  - "(.+)"
resync_period_hours: -5`,
		wantErr: true,
	}}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			cfg, err := ParseRepoConfigFile([]byte(tc.content), "o", "r")
			if tc.wantErr {
				if err == nil {
					t.Fatal("ParseRepoConfigFile: got = nil, want error")
				}
				return
			}
			if err != nil {
				t.Fatalf("ParseRepoConfigFile: unexpected error %v", err)
			}
			if cfg.Period != tc.wantPeriod {
				t.Errorf("Period: got = %v, want %v", cfg.Period, tc.wantPeriod)
			}
		})
	}
}

func TestParseRepoConfigFileExcludePatterns(t *testing.T) {
	content := []byte(`
path_patterns:
  - "(bots/[^/]+)/.*\\.go"
exclude_patterns:
  - ".*/testdata/.*"
resync_period_hours: 24
`)
	cfg, err := ParseRepoConfigFile(content, "chainguard-dev", "mono")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if key, ok := cfg.Matcher.Match("bots/skillup/testdata/foo.go"); ok {
		t.Errorf("excluded path should not match, got %q", key)
	}
	if _, ok := cfg.Matcher.Match("bots/skillup/main.go"); !ok {
		t.Errorf("non-excluded matching path should match")
	}
}
