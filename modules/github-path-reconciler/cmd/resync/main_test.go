/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/google/go-github/v88/github"
)

// fakeGit serves the trees of a repository holding files on branch main the
// way GitHub does: entries relative to the requested tree, only direct
// entries when not recursive, and each tree named by an opaque SHA (here the
// hex of its directory, "" being the root). A recursive listing of a
// directory in truncated is cut off, and so is a one-level listing of a
// directory in truncatedLevel. Requests must name main once, for the root,
// and every other tree by its SHA.
func fakeGit(t *testing.T, files, truncated, truncatedLevel []string) *github.GitService {
	t.Helper()
	var branchLookups atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		treeish := strings.TrimPrefix(r.URL.Path, "/repos/o/r/git/trees/")
		dir := ""
		if treeish == "main" {
			if branchLookups.Add(1) > 1 {
				t.Errorf("branch main looked up more than once")
			}
		} else {
			b, err := hex.DecodeString(treeish)
			if err != nil {
				t.Errorf("tree %q is not a SHA", treeish)
				http.Error(w, "bad tree", http.StatusBadRequest)
				return
			}
			dir = string(b)
		}
		recursive := r.URL.Query().Get("recursive") == "1"
		tree := &github.Tree{
			SHA:       new(hex.EncodeToString([]byte(dir))),
			Truncated: new(slices.Contains(truncated, dir) && recursive || slices.Contains(truncatedLevel, dir) && !recursive),
		}
		if !tree.GetTruncated() {
			prefix := ""
			if dir != "" {
				prefix = dir + "/"
			}
			subdirs := map[string]struct{}{}
			for _, file := range files {
				rel, ok := strings.CutPrefix(file, prefix)
				if !ok {
					continue
				}
				sub, _, nested := strings.Cut(rel, "/")
				if nested {
					subdirs[sub] = struct{}{}
				}
				if recursive || !nested {
					tree.Entries = append(tree.Entries, &github.TreeEntry{Path: new(rel), Type: new("blob")})
				}
			}
			for sub := range subdirs {
				sha := hex.EncodeToString([]byte(prefix + sub))
				tree.Entries = append(tree.Entries, &github.TreeEntry{Path: new(sub), Type: new("tree"), SHA: new(sha)})
			}
		}
		if err := json.NewEncoder(w).Encode(tree); err != nil {
			t.Errorf("encode tree: %v", err)
		}
	}))
	t.Cleanup(srv.Close)

	client, err := github.NewClient(github.WithHTTPClient(srv.Client()), github.WithURLs(new(srv.URL+"/"), nil))
	if err != nil {
		t.Fatalf("create GitHub client: %v", err)
	}
	return client.Git
}

func TestListFiles(t *testing.T) {
	files := []string{"README.md", "bots/a.go", "docs/100%/a#b.md", "env/chainops.dev/a.tf", "env/enforce.dev/b.tf"}

	tests := []struct {
		name           string
		truncated      []string
		truncatedLevel []string
		wantErr        string
	}{{
		name: "nothing truncated",
	}, {
		name:      "truncated root",
		truncated: []string{""},
	}, {
		name:      "truncated root and subdirectories",
		truncated: []string{"", "docs", "env"},
	}, {
		name:           "directory truncated one level deep",
		truncated:      []string{"", "env"},
		truncatedLevel: []string{"env"},
		wantErr:        `tree "env"`,
	}}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := listFiles(t.Context(), fakeGit(t, files, tt.truncated, tt.truncatedLevel), "o", "r", "main", "")
			if tt.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), tt.wantErr) {
					t.Fatalf("listFiles(): got error = %v, want one containing %q", err, tt.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatalf("listFiles(): unexpected error: %v", err)
			}
			slices.Sort(got)
			if !slices.Equal(got, files) {
				t.Errorf("listFiles(): got = %q, want = %q", got, files)
			}
		})
	}
}
