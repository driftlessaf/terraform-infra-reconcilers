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
	"testing"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"chainguard.dev/driftlessaf/workqueue"
	"chainguard.dev/driftlessaf/workqueue/inmem"
)

func TestDrain(t *testing.T) {
	key := fmt.Sprintf("key-%d", rand.Int64())
	priority := rand.Int64N(1000)
	queue := func(opts workqueue.Options) func(*testing.T, *deadLetterQueue) {
		return func(t *testing.T, q *deadLetterQueue) {
			t.Helper()
			if err := q.Interface.Queue(t.Context(), key, opts); err != nil {
				t.Fatalf("Queue: got = %v, want = nil", err)
			}
		}
	}

	tests := []struct {
		name string
		// setup puts the dead-lettered key in the state the case names.
		setup func(*testing.T, *deadLetterQueue)
		// wantListed is whether Enumerate lists the key as queued.
		wantListed     bool
		wantQueued     []queueCall
		wantReenqueued int
		wantSkipped    int
		wantFailed     int
	}{{
		name:        "queued",
		setup:       queue(workqueue.Options{}),
		wantListed:  true,
		wantSkipped: 1,
	}, {
		name: "in progress",
		setup: func(t *testing.T, q *deadLetterQueue) {
			queue(workqueue.Options{})(t, q)
			_, queued, _, err := q.Interface.Enumerate(t.Context())
			if err != nil {
				t.Fatalf("Enumerate: got = %v, want = nil", err)
			}
			if len(queued) != 1 {
				t.Fatalf("queued keys: got = %d, want = 1", len(queued))
			}
			if _, err := queued[0].Start(t.Context()); err != nil {
				t.Fatalf("Start: got = %v, want = nil", err)
			}
		},
		wantSkipped: 1,
	}, {
		name:        "queued in a backoff",
		setup:       queue(workqueue.Options{NotBefore: time.Now().Add(time.Hour)}),
		wantSkipped: 1,
	}, {
		name:           "dead-lettered only",
		setup:          func(*testing.T, *deadLetterQueue) {},
		wantQueued:     []queueCall{{key: key, priority: priority}},
		wantReenqueued: 1,
	}, {
		name: "completed since Enumerate",
		setup: func(_ *testing.T, q *deadLetterQueue) {
			q.getErr = status.Errorf(codes.NotFound, "key %q not found", key)
		},
		wantSkipped: 1,
	}, {
		name: "Get fails",
		setup: func(_ *testing.T, q *deadLetterQueue) {
			q.getErr = status.Error(codes.Unavailable, "unavailable")
		},
		wantFailed: 1,
	}, {
		name: "Queue fails",
		setup: func(_ *testing.T, q *deadLetterQueue) {
			q.queueErr = errors.New("queue failed")
		},
		wantQueued: []queueCall{{key: key, priority: priority}},
		wantFailed: 1,
	}}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			q := &deadLetterQueue{
				Interface: inmem.NewWorkQueue(10),
				dead:      []workqueue.DeadLetteredKey{deadLetteredKey{name: key, priority: priority}},
			}
			tc.setup(t, q)

			_, queued, _, err := q.Enumerate(t.Context())
			if err != nil {
				t.Fatalf("Enumerate: got = %v, want = nil", err)
			}
			listed := slices.ContainsFunc(queued, func(k workqueue.QueuedKey) bool { return k.Name() == key })
			if listed != tc.wantListed {
				t.Fatalf("listed as queued: got = %v, want = %v", listed, tc.wantListed)
			}

			reenqueued, skipped, failed, err := drain(t.Context(), q)
			if err != nil {
				t.Fatalf("drain: got = %v, want = nil", err)
			}
			if !slices.Equal(q.queued, tc.wantQueued) {
				t.Errorf("Queue calls: got = %v, want = %v", q.queued, tc.wantQueued)
			}
			if reenqueued != tc.wantReenqueued {
				t.Errorf("reenqueued: got = %v, want = %v", reenqueued, tc.wantReenqueued)
			}
			if skipped != tc.wantSkipped {
				t.Errorf("skipped: got = %v, want = %v", skipped, tc.wantSkipped)
			}
			if failed != tc.wantFailed {
				t.Errorf("failed: got = %v, want = %v", failed, tc.wantFailed)
			}
		})
	}
}

func TestDrainEnumerateError(t *testing.T) {
	want := errors.New("enumerate failed")
	q := &deadLetterQueue{Interface: inmem.NewWorkQueue(10), enumerateErr: want}

	if _, _, _, err := drain(t.Context(), q); !errors.Is(err, want) {
		t.Errorf("drain: got = %v, want = %v", err, want)
	}
	if len(q.queued) != 0 {
		t.Errorf("Queue calls: got = %v, want = none", q.queued)
	}
}

type queueCall struct {
	key      string
	priority int64
}

// deadLetterQueue adds dead-lettered keys to the in-memory queue, which keeps
// none. Queued and in-progress state stays with the in-memory queue, so
// Enumerate leaves out a key waiting in a backoff while Get reports it.
type deadLetterQueue struct {
	workqueue.Interface
	dead         []workqueue.DeadLetteredKey
	enumerateErr error
	getErr       error
	queueErr     error
	queued       []queueCall
}

func (q *deadLetterQueue) Enumerate(ctx context.Context) ([]workqueue.ObservedInProgressKey, []workqueue.QueuedKey, []workqueue.DeadLetteredKey, error) {
	if q.enumerateErr != nil {
		return nil, nil, nil, q.enumerateErr
	}
	wip, next, _, err := q.Interface.Enumerate(ctx)
	return wip, next, q.dead, err
}

// Get reports a key that is neither in progress nor queued as dead-lettered
// when it is one of q.dead, the order of lookups the storage-backed queue uses.
func (q *deadLetterQueue) Get(ctx context.Context, key string) (*workqueue.KeyState, error) {
	if q.getErr != nil {
		return nil, q.getErr
	}
	state, err := q.Interface.Get(ctx, key)
	if status.Code(err) != codes.NotFound {
		return state, err
	}
	for _, dlk := range q.dead {
		if dlk.Name() == key {
			return &workqueue.KeyState{
				Key:      key,
				Status:   workqueue.KeyState_DEAD_LETTER,
				Priority: dlk.Priority(),
			}, nil
		}
	}
	return nil, err
}

func (q *deadLetterQueue) Queue(_ context.Context, key string, opts workqueue.Options) error {
	q.queued = append(q.queued, queueCall{key: key, priority: opts.Priority})
	return q.queueErr
}

type deadLetteredKey struct {
	name     string
	priority int64
}

func (k deadLetteredKey) Name() string             { return k.name }
func (k deadLetteredKey) Priority() int64          { return k.priority }
func (k deadLetteredKey) GetFailedTime() time.Time { return time.Time{} }
func (k deadLetteredKey) GetAttempts() int         { return 0 }
