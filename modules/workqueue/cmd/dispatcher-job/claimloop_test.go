/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"sync/atomic"
	"testing"
	"testing/synctest"
	"time"

	"chainguard.dev/driftlessaf/workqueue"
	"chainguard.dev/driftlessaf/workqueue/dispatcher"
	"chainguard.dev/driftlessaf/workqueue/inmem"
)

// claimHarness runs claimLoop the way main does — the dispatcher's own
// HandleAsync over a reservingQueue, with releaseSlot and countCalls around
// the callback — against the real in-memory workqueue. Keys are queued on a
// schedule, as runs are created; each callback holds its key for hold.
type claimHarness struct {
	q       workqueue.Interface
	start   time.Time
	hold    time.Duration
	passErr map[int]error // pass index -> an error to report from that pass's future

	mu        sync.Mutex
	arrived   map[string]time.Duration
	claimedAt map[string]time.Duration
	batches   []int
	running   int
	maxRun    int

	inUse, claimed atomic.Int64
}

func newClaimHarness(t *testing.T, arrivals []time.Duration, hold time.Duration, q workqueue.Interface) *claimHarness {
	t.Helper()
	h := &claimHarness{q: q, start: time.Now(), hold: hold, arrived: map[string]time.Duration{}, claimedAt: map[string]time.Duration{}}
	for i, at := range arrivals {
		key := fmt.Sprintf("key-%02d", i)
		h.arrived[key] = at
		queue := func() {
			if err := q.Queue(context.WithoutCancel(t.Context()), key, workqueue.Options{Priority: int64(-i)}); err != nil {
				t.Errorf("Queue(%s): %v", key, err)
			}
		}
		if at == 0 {
			queue()
		} else {
			time.AfterFunc(at, queue)
		}
	}
	return h
}

func (h *claimHarness) callback(ctx context.Context, key string, _ workqueue.Options) error {
	h.mu.Lock()
	h.claimedAt[key] = time.Since(h.start)
	h.running++
	h.maxRun = max(h.maxRun, h.running)
	h.mu.Unlock()
	defer func() {
		h.mu.Lock()
		h.running--
		h.mu.Unlock()
	}()
	select {
	case <-time.After(h.hold):
	case <-ctx.Done():
	}
	return nil
}

func (h *claimHarness) run(ctx context.Context, batch int, window, poll time.Duration) error {
	claims := &reservingQueue{Interface: h.q, inUse: &h.inUse, first: func(string) {}}
	callback := releaseSlot(countCalls(h.callback, &h.claimed), &h.inUse)
	pass := func(ctx context.Context, n int) dispatcher.Future {
		h.mu.Lock()
		idx := len(h.batches)
		h.batches = append(h.batches, n)
		passErr := h.passErr[idx]
		h.mu.Unlock()
		fut := dispatcher.HandleAsync(ctx, claims, 10, n, callback, 0)
		return func() error { return errors.Join(fut(), passErr) }
	}
	return claimLoop(ctx, batch, window, poll, &h.inUse, &h.claimed, pass)
}

func TestClaimLoop(t *testing.T) {
	errPass := errors.New("enumerate failed")
	for _, tc := range []struct {
		name        string
		batch       int
		window      time.Duration
		poll        time.Duration
		arrivals    []time.Duration
		hold        time.Duration
		passErr     map[int]error
		wantClaimed int
		wantLatest  time.Duration // no key may wait for a claim longer than this after it was queued
		wantElapsed time.Duration // upper bound on how long the loop ran
		wantErr     error
	}{{
		name:        "no window is the single pass at startup",
		batch:       2,
		poll:        10 * time.Second,
		arrivals:    []time.Duration{0, 0, 0, 30 * time.Second},
		hold:        time.Minute,
		wantClaimed: 2,
		wantLatest:  0,
		wantElapsed: time.Minute,
	}, {
		name:        "an idle job exits at once instead of polling",
		batch:       6,
		window:      10 * time.Minute,
		poll:        10 * time.Second,
		wantClaimed: 0,
		wantElapsed: 0,
	}, {
		name:        "keys queued while the job runs are claimed into free slots within a poll",
		batch:       4,
		window:      10 * time.Minute,
		poll:        10 * time.Second,
		arrivals:    []time.Duration{0, 0, 30 * time.Second, 45 * time.Second, 5 * time.Minute},
		hold:        time.Minute,
		wantClaimed: 4, // the key at 5m is queued after the job ran dry and exited
		wantLatest:  15 * time.Second,
		wantElapsed: 2 * time.Minute,
	}, {
		name:        "a job whose slots free up claims again before it exits",
		batch:       2,
		window:      10 * time.Minute,
		poll:        10 * time.Second,
		arrivals:    []time.Duration{0, 0, 0, 0},
		hold:        time.Minute,
		wantClaimed: 4,
		wantLatest:  time.Minute,
		wantElapsed: 2 * time.Minute,
	}, {
		name:        "claiming stops at the window and the job then drains",
		batch:       1,
		window:      time.Minute,
		poll:        10 * time.Second,
		arrivals:    []time.Duration{0, 0, 0},
		hold:        50 * time.Second,
		wantClaimed: 2, // the third key would be claimed after the window
		wantLatest:  50 * time.Second,
		wantElapsed: 100 * time.Second,
	}, {
		name:        "a failed pass is reported after the keys drain, and claiming goes on",
		batch:       1,
		window:      10 * time.Minute,
		poll:        10 * time.Second,
		arrivals:    []time.Duration{0, 0},
		hold:        30 * time.Second,
		passErr:     map[int]error{0: errPass},
		wantClaimed: 2,
		wantLatest:  30 * time.Second,
		wantElapsed: time.Minute,
		wantErr:     errPass,
	}} {
		t.Run(tc.name, func(t *testing.T) {
			synctest.Test(t, func(t *testing.T) {
				h := newClaimHarness(t, tc.arrivals, tc.hold, inmem.NewWorkQueue(10))
				h.passErr = tc.passErr
				err := h.run(t.Context(), tc.batch, tc.window, tc.poll)
				elapsed := time.Since(h.start)
				if !errors.Is(err, tc.wantErr) || (err != nil) != (tc.wantErr != nil) {
					t.Errorf("claimLoop error: got = %v, want = %v", err, tc.wantErr)
				}
				if got := len(h.claimedAt); got != tc.wantClaimed {
					t.Errorf("keys claimed: got = %d, want = %d (%v)", got, tc.wantClaimed, h.claimedAt)
				}
				for key, at := range h.claimedAt {
					if wait := at - h.arrived[key]; wait > tc.wantLatest {
						t.Errorf("%s queued at %s waited %s for a claim, want at most %s", key, h.arrived[key], wait, tc.wantLatest)
					}
				}
				if elapsed > tc.wantElapsed {
					t.Errorf("claimLoop ran for %s, want at most %s", elapsed, tc.wantElapsed)
				}
				if h.maxRun > tc.batch {
					t.Errorf("most callbacks at once: got = %d, want at most the batch %d", h.maxRun, tc.batch)
				}
				for i, n := range h.batches {
					if n <= 0 || n > tc.batch {
						t.Errorf("pass %d offered batch %d, want 1..%d", i, n, tc.batch)
					}
				}
				if got := h.inUse.Load(); got != 0 {
					t.Errorf("slots still in use after claimLoop returned: got = %d, want = 0", got)
				}
			})
		})
	}
}

// slowStartQueue is the in-memory queue with each successful Start taking
// startDelay to return, as a GCS claim does when its in-progress copy has
// landed and the queued object's delete is still in flight. A Start that
// fails returns at once.
type slowStartQueue struct {
	workqueue.Interface
	startDelay time.Duration
}

func (q slowStartQueue) Enumerate(ctx context.Context) ([]workqueue.ObservedInProgressKey, []workqueue.QueuedKey, []workqueue.DeadLetteredKey, error) {
	wip, next, dead, err := q.Interface.Enumerate(ctx)
	slow := make([]workqueue.QueuedKey, 0, len(next))
	for _, k := range next {
		slow = append(slow, slowStartKey{QueuedKey: k, delay: q.startDelay})
	}
	return wip, slow, dead, err
}

type slowStartKey struct {
	workqueue.QueuedKey
	delay time.Duration
}

func (k slowStartKey) Start(ctx context.Context) (workqueue.OwnedInProgressKey, error) {
	oip, err := k.QueuedKey.Start(ctx)
	if err != nil {
		return nil, err
	}
	time.Sleep(k.delay) //nolint:forbidigo // synctest fake time: the Start's in-flight interval under test
	return oip, nil
}

// TestClaimLoopCountsClaimsStillStarting: a claim holds its slot from the
// moment its Start begins, so a poll that lands while a claim is still
// completing its Start does not offer that slot to another pass, and the
// job never carries more callbacks than its batch.
func TestClaimLoopCountsClaimsStillStarting(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		arrivals := make([]time.Duration, 6)
		h := newClaimHarness(t, arrivals, time.Minute, slowStartQueue{Interface: inmem.NewWorkQueue(10), startDelay: 30 * time.Second})
		if err := h.run(t.Context(), 2, 10*time.Minute, 10*time.Second); err != nil {
			t.Fatalf("claimLoop: %v", err)
		}
		if h.maxRun > 2 {
			t.Errorf("most callbacks at once: got = %d, want at most the batch of 2", h.maxRun)
		}
		if got := len(h.claimedAt); got != 6 {
			t.Errorf("keys claimed: got = %d, want = 6", got)
		}
	})
}

// TestClaimLoopStopsClaimingOnCancel: a job told to stop (SIGTERM, the job
// timeout) claims nothing more and returns once its keys have seen the
// cancellation.
func TestClaimLoopStopsClaimingOnCancel(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		h := newClaimHarness(t, []time.Duration{0, time.Second, 2 * time.Second}, time.Hour, inmem.NewWorkQueue(10))
		ctx, cancel := context.WithCancel(t.Context())
		time.AfterFunc(3*time.Second, cancel)
		if err := h.run(ctx, 3, 10*time.Minute, 10*time.Second); err != nil {
			t.Errorf("claimLoop: got = %v, want nil", err)
		}
		if got := len(h.claimedAt); got != 1 {
			t.Errorf("keys claimed: got = %d, want = 1 (%v): the job claimed after it was told to stop", got, h.claimedAt)
		}
		if elapsed := time.Since(h.start); elapsed != 3*time.Second {
			t.Errorf("claimLoop returned after %s, want 3s: when the cancellation reached its key", elapsed)
		}
	})
}
