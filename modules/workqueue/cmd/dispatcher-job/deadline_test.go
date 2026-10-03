/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"errors"
	"fmt"
	"math/rand/v2"
	"slices"
	"sync"
	"testing"
	"testing/synctest"
	"time"

	"chainguard.dev/driftlessaf/workqueue"
	"chainguard.dev/driftlessaf/workqueue/dispatcher"
	"chainguard.dev/driftlessaf/workqueue/inmem"
)

// untilDone is a reconcile that never finishes on its own: it returns only when
// its context ends, the way a hung reconcile returns at the job's timeout.
func untilDone(ctx context.Context, _ string, _ workqueue.Options) error {
	<-ctx.Done()
	return ctx.Err()
}

// withDeadline hands the reconcile a context that ends at the deadline, and the
// reconcile's error passes through.
func TestWithDeadline(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		deadline := time.Now().Add(time.Minute)
		var gotDeadline time.Time
		err := withDeadline(func(ctx context.Context, key string, opts workqueue.Options) error {
			gotDeadline, _ = ctx.Deadline()
			return untilDone(ctx, key, opts)
		}, deadline)(t.Context(), "key", workqueue.Options{})

		if !gotDeadline.Equal(deadline) {
			t.Errorf("reconcile deadline: got = %v, want = %v", gotDeadline, deadline)
		}
		if !errors.Is(err, context.DeadlineExceeded) {
			t.Errorf("error: got = %v, want = %v", err, context.DeadlineExceeded)
		}
		if got, want := time.Now(), deadline; !got.Equal(want) {
			t.Errorf("returned at: got = %v, want = %v", got, want)
		}
	})
}

// A reconcile that runs out its deadline spends one of the key's attempts, so a
// key whose reconcile always hangs dead-letters after maxRetry passes rather
// than coming back forever, as it does when the job's own shutdown interrupts
// it.
func TestDeadlineDeadLettersHungKey(t *testing.T) {
	const maxRetry = 3
	synctest.Test(t, func(t *testing.T) {
		ctx := t.Context()
		key := fmt.Sprintf("key-%d", rand.Int64())
		wq := &deadletterRecorder{Interface: inmem.NewWorkQueue(10)}
		if err := wq.Queue(ctx, key, workqueue.Options{}); err != nil {
			t.Fatalf("Queue: got = %v, want = nil", err)
		}

		for pass := range maxRetry + 1 {
			callback := withDeadline(untilDone, time.Now().Add(time.Minute))
			if err := dispatcher.HandleAsync(ctx, wq, 1, 1, callback, maxRetry)(); err != nil {
				t.Fatalf("pass %d: HandleAsync: got = %v, want = nil", pass, err)
			}
			// Let the retry backoff pass so the next pass can claim the key.
			time.Sleep(workqueue.MaximumBackoffPeriod)
		}

		if got, want := wq.deadLettered(), []string{key}; !slices.Equal(got, want) {
			t.Errorf("dead-lettered keys: got = %v, want = %v", got, want)
		}
	})
}

// deadletterRecorder records the keys the dispatcher dead-letters; the
// in-memory queue drops them without a trace.
type deadletterRecorder struct {
	workqueue.Interface
	mu   sync.Mutex
	dead []string
}

func (q *deadletterRecorder) Enumerate(ctx context.Context) ([]workqueue.ObservedInProgressKey, []workqueue.QueuedKey, []workqueue.DeadLetteredKey, error) {
	wip, next, dead, err := q.Interface.Enumerate(ctx)
	for i, k := range next {
		next[i] = recordingKey{QueuedKey: k, q: q}
	}
	return wip, next, dead, err
}

func (q *deadletterRecorder) deadLettered() []string {
	q.mu.Lock()
	defer q.mu.Unlock()
	return slices.Clone(q.dead)
}

type recordingKey struct {
	workqueue.QueuedKey
	q *deadletterRecorder
}

func (k recordingKey) Start(ctx context.Context) (workqueue.OwnedInProgressKey, error) {
	o, err := k.QueuedKey.Start(ctx)
	if err != nil {
		return nil, err
	}
	return recordingOwnedKey{OwnedInProgressKey: o, q: k.q}, nil
}

type recordingOwnedKey struct {
	workqueue.OwnedInProgressKey
	q *deadletterRecorder
}

func (o recordingOwnedKey) Deadletter(ctx context.Context) error {
	o.q.mu.Lock()
	o.q.dead = append(o.q.dead, o.Name())
	o.q.mu.Unlock()
	return o.OwnedInProgressKey.Deadletter(ctx)
}
