/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package enqueue

import (
	"context"
	"testing"
	"time"

	"chainguard.dev/driftlessaf/workqueue"
)

type fakeQueue struct {
	workqueue.Interface

	key  string
	opts workqueue.Options
}

func (f *fakeQueue) Queue(_ context.Context, key string, opts workqueue.Options) error {
	f.key = key
	f.opts = opts
	return nil
}

func TestProcessDelaySeconds(t *testing.T) {
	tests := []struct {
		name         string
		delaySeconds int64
		wantDelay    time.Duration
	}{{
		name:         "positive delay becomes NotBefore",
		delaySeconds: 30,
		wantDelay:    30 * time.Second,
	}, {
		name:         "zero delay leaves NotBefore unset",
		delaySeconds: 0,
	}, {
		name:         "negative delay leaves NotBefore unset",
		delaySeconds: -5,
	}}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			fq := &fakeQueue{}
			s := NewServer(fq)

			before := time.Now().UTC()
			if _, err := s.Process(t.Context(), &workqueue.ProcessRequest{
				Key:          "test-key",
				Priority:     3,
				DelaySeconds: tt.delaySeconds,
			}); err != nil {
				t.Fatalf("Process() = %v", err)
			}
			after := time.Now().UTC()

			if fq.key != "test-key" {
				t.Errorf("queued key = %q, want %q", fq.key, "test-key")
			}
			if fq.opts.Priority != 3 {
				t.Errorf("queued priority = %d, want 3", fq.opts.Priority)
			}

			if tt.wantDelay == 0 {
				if !fq.opts.NotBefore.IsZero() {
					t.Errorf("NotBefore = %v, want zero", fq.opts.NotBefore)
				}
				return
			}

			earliest := before.Add(tt.wantDelay)
			latest := after.Add(tt.wantDelay)
			if fq.opts.NotBefore.Before(earliest) || fq.opts.NotBefore.After(latest) {
				t.Errorf("NotBefore = %v, want within [%v, %v]", fq.opts.NotBefore, earliest, latest)
			}
		})
	}
}
