/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"errors"
	"sync/atomic"
	"testing"
	"testing/synctest"
	"time"

	"github.com/prometheus/client_golang/prometheus"

	"chainguard.dev/driftlessaf/workqueue"
)

// TestCountCalls pins that the wrapper counts every key it is handed, failed
// ones included — a failed reconcile still records metrics that need a scrape
// — and passes the callback's arguments and result through untouched.
func TestCountCalls(t *testing.T) {
	errBoom := errors.New("boom")
	var gotKeys []string
	inner := func(_ context.Context, key string, opts workqueue.Options) error {
		gotKeys = append(gotKeys, key)
		if opts.Priority != 7 {
			t.Errorf("priority: got = %d, want = 7", opts.Priority)
		}
		if key == "bad" {
			return errBoom
		}
		return nil
	}

	var n atomic.Int64
	f := countCalls(inner, &n)
	if got := n.Load(); got != 0 {
		t.Fatalf("count before any call: got = %d, want = 0", got)
	}
	if err := f(t.Context(), "good", workqueue.Options{Priority: 7}); err != nil {
		t.Errorf("good key: got err = %v, want nil", err)
	}
	if err := f(t.Context(), "bad", workqueue.Options{Priority: 7}); !errors.Is(err, errBoom) {
		t.Errorf("bad key: got err = %v, want %v", err, errBoom)
	}
	if got := n.Load(); got != 2 {
		t.Errorf("count: got = %d, want = 2", got)
	}
	if len(gotKeys) != 2 || gotKeys[0] != "good" || gotKeys[1] != "bad" {
		t.Errorf("keys passed through: got = %v, want = [good bad]", gotKeys)
	}
}

func TestShouldReport(t *testing.T) {
	// Anchored on a known wall-clock instant: 12:00:00 UTC is a multiple of
	// every cadence under test, so the residues below are the clock minutes.
	base := time.Date(2026, 9, 22, 12, 0, 0, 0, time.UTC)
	for _, tc := range []struct {
		name  string
		at    time.Time
		every time.Duration
		want  bool
	}{{
		name:  "on the tick",
		at:    base,
		every: 5 * time.Minute,
		want:  true,
	}, {
		name:  "seconds into the tick still counts",
		at:    base.Add(37 * time.Second),
		every: 5 * time.Minute,
		want:  true,
	}, {
		name:  "one minute past the tick",
		at:    base.Add(time.Minute),
		every: 5 * time.Minute,
		want:  false,
	}, {
		name:  "four minutes past the tick",
		at:    base.Add(4 * time.Minute),
		every: 5 * time.Minute,
		want:  false,
	}, {
		name:  "next tick",
		at:    base.Add(5 * time.Minute),
		every: 5 * time.Minute,
		want:  true,
	}, {
		name:  "a one-minute cadence never skips",
		at:    base.Add(3 * time.Minute),
		every: time.Minute,
		want:  true,
	}} {
		t.Run(tc.name, func(t *testing.T) {
			if got := shouldReport(tc.at, tc.every); got != tc.want {
				t.Errorf("shouldReport(%s, %s): got = %v, want = %v", tc.at.Format(time.RFC3339), tc.every, got, tc.want)
			}
		})
	}
}

// TestShouldReportCadence pins the rate rather than individual instants: over an
// hour of per-minute executions the gate must fire often enough that the alert's
// auto_close window never elapses without a sample.
func TestShouldReportCadence(t *testing.T) {
	const autoClose = time.Hour
	base := time.Date(2026, 9, 22, 12, 0, 0, 0, time.UTC)

	var fired int
	var longestGap time.Duration
	var last time.Time
	for i := range 60 {
		at := base.Add(time.Duration(i) * time.Minute)
		if !shouldReport(at, reportEvery) {
			continue
		}
		fired++
		if !last.IsZero() && at.Sub(last) > longestGap {
			longestGap = at.Sub(last)
		}
		last = at
	}
	if want := int(time.Hour / reportEvery); fired != want {
		t.Errorf("reports in an hour: got = %d, want = %d", fired, want)
	}
	if longestGap >= autoClose {
		t.Errorf("longest gap between reports: got = %s, want < %s (auto_close)", longestGap, autoClose)
	}
}

func TestDeadLettered(t *testing.T) {
	for _, tc := range []struct {
		name   string
		values map[string]float64
		want   float64
	}{{
		name: "gauge absent",
		want: 0,
	}, {
		name:   "drained queue",
		values: map[string]float64{"a": 0},
		want:   0,
	}, {
		name:   "summed across queues",
		values: map[string]float64{"a": 7, "b": 3},
		want:   10,
	}} {
		t.Run(tc.name, func(t *testing.T) {
			reg := prometheus.NewRegistry()
			if tc.values != nil {
				g := prometheus.NewGaugeVec(prometheus.GaugeOpts{
					Name: "workqueue_dead_lettered_keys",
				}, []string{"queue_name"})
				reg.MustRegister(g)
				for q, v := range tc.values {
					g.WithLabelValues(q).Set(v)
				}
			}
			// A neighbouring gauge must not be counted.
			other := prometheus.NewGauge(prometheus.GaugeOpts{Name: "workqueue_queued_keys"})
			other.Set(42)
			reg.MustRegister(other)

			if got := deadLettered(t.Context(), reg); got != tc.want {
				t.Errorf("deadLettered: got = %v, want = %v", got, tc.want)
			}
		})
	}
}

// The await tests run under synctest so that "how long did await block" is an
// exact fake-clock reading rather than a wall-clock margin: each one
// distinguishes the paths by the duration it returns after, which is only a
// sound assertion when the clock cannot drift.

func TestScrapeSignalAwaitScraped(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		s := newScrapeSignal()
		reg := prometheus.NewRegistry()
		reg.MustRegister(s)

		const flush = 5 * time.Second
		start := time.Now()
		done := make(chan struct{})
		go func() {
			defer close(done)
			s.await(t.Context(), time.Hour, flush)
		}()

		// Let await reach its select first, so the scrape below is unambiguously
		// the one it is waiting for and not the stale token it discards.
		synctest.Wait()
		if _, err := reg.Gather(); err != nil {
			t.Fatalf("Gather() = %v", err)
		}

		<-done
		if got := time.Since(start); got != flush {
			t.Errorf("await after a scrape returned at %s, want = %s (the flush window)", got, flush)
		}
	})
}

// TestScrapeSignalAwaitDiscardsStaleScrape pins the pre-drain the whole fix
// rests on. deadLettered gathers the registry to read the gauge, which trips
// the collector and leaves a token behind. If await accepted that token it
// would return immediately and the job would exit before the sidecar ever
// scraped it — the flap this change closes.
func TestScrapeSignalAwaitDiscardsStaleScrape(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		s := newScrapeSignal()
		reg := prometheus.NewRegistry()
		reg.MustRegister(s)

		if _, err := reg.Gather(); err != nil {
			t.Fatalf("Gather() = %v", err)
		}

		// flush is far longer than wait, so accepting the stale token is not just
		// early, it returns at a different instant than either honest path.
		const wait = 30 * time.Second
		start := time.Now()
		s.await(t.Context(), wait, time.Hour)
		if got := time.Since(start); got != wait {
			t.Errorf("await returned at %s, want = %s: the stale scrape must not satisfy it", got, wait)
		}
	})
}

func TestScrapeSignalAwaitTimesOut(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		const wait = 30 * time.Second
		start := time.Now()
		newScrapeSignal().await(t.Context(), wait, time.Hour)
		if got := time.Since(start); got != wait {
			t.Errorf("await with no scrape returned at %s, want = %s", got, wait)
		}
	})
}

// TestScrapeSignalAwaitContextCanceled covers SIGTERM arriving while the job is
// holding for a scrape: Cloud Run is already tearing the execution down, so
// await must let go rather than spend its whole budget on a scrape that is not
// coming.
func TestScrapeSignalAwaitContextCanceled(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		ctx, cancel := context.WithCancel(t.Context())
		defer cancel()

		start := time.Now()
		done := make(chan struct{})
		go func() {
			defer close(done)
			newScrapeSignal().await(ctx, time.Hour, time.Hour)
		}()

		synctest.Wait()
		cancel()

		<-done
		if got := time.Since(start); got != 0 {
			t.Errorf("await returned at %s after cancellation, want it to return at once", got)
		}
	})
}

// TestScrapeSignalAwaitContextCanceledDuringFlush covers the same signal
// arriving in the second half of await, after the scrape has landed.
func TestScrapeSignalAwaitContextCanceledDuringFlush(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		ctx, cancel := context.WithCancel(t.Context())
		defer cancel()

		s := newScrapeSignal()
		reg := prometheus.NewRegistry()
		reg.MustRegister(s)

		start := time.Now()
		done := make(chan struct{})
		go func() {
			defer close(done)
			s.await(ctx, time.Hour, time.Hour)
		}()

		synctest.Wait()
		if _, err := reg.Gather(); err != nil {
			t.Fatalf("Gather() = %v", err)
		}
		// await has taken the scrape and is now in the flush wait.
		synctest.Wait()
		cancel()

		<-done
		if got := time.Since(start); got != 0 {
			t.Errorf("await returned at %s after cancellation mid-flush, want it to return at once", got)
		}
	})
}
