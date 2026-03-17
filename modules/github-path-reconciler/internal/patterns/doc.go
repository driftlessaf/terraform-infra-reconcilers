/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

// Package patterns provides utilities for parsing and validating regex patterns
// used to match GitHub file paths. Each pattern must have exactly one capture
// group, which is used to extract the relevant portion of the matched path.
package patterns
