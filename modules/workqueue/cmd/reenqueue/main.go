/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"os"
	"os/signal"
	"syscall"

	"cloud.google.com/go/storage"
	"github.com/chainguard-dev/clog"
	_ "github.com/chainguard-dev/clog/gcp/init"
	"github.com/sethvargo/go-envconfig"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"chainguard.dev/driftlessaf/workqueue"
	"chainguard.dev/driftlessaf/workqueue/gcs"
	"github.com/chainguard-dev/terraform-infra-common/pkg/httpmetrics"
)

var env = envconfig.MustProcess(context.Background(), &struct {
	Mode        string `env:"WORKQUEUE_MODE"`   // required; enforced in main()
	Bucket      string `env:"WORKQUEUE_BUCKET"` // required; enforced in main()
	Concurrency int    `env:"WORKQUEUE_CONCURRENCY,default=100"`
}{})

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	if env.Mode == "" {
		clog.FatalContextf(ctx, "WORKQUEUE_MODE is required")
	}
	if env.Bucket == "" {
		clog.FatalContextf(ctx, "WORKQUEUE_BUCKET is required")
	}

	go httpmetrics.ServeMetrics()

	if env.Mode != "gcs" {
		clog.FatalContextf(ctx, "Unsupported mode: %q, only 'gcs' is supported", env.Mode)
	}

	// Create GCS client and workqueue
	cl, err := storage.NewClient(ctx)
	if err != nil {
		clog.FatalContextf(ctx, "Failed to create storage client: %v", err)
	}
	defer cl.Close()

	_, _, failed, err := drain(ctx, gcs.NewWorkQueue(cl.Bucket(env.Bucket), env.Concurrency))
	if err != nil {
		clog.FatalContextf(ctx, "Failed to enumerate workqueue: %v", err)
	}
	if failed > 0 {
		clog.FatalContextf(ctx, "Some keys failed to reenqueue")
	}
}

// drain queues every dead-lettered key that is neither queued nor in progress.
//
// A dead-lettered key stays dead-lettered until it completes, so a key an
// earlier drain queued is still listed while it retries. Queueing it again
// would reset its attempt count, which the retry limit is checked against.
// Get reads the three states one after another, so a key the dispatcher
// starts between those reads can still be queued again.
//
// The error is non-nil only when the workqueue cannot be enumerated.
func drain(ctx context.Context, wq workqueue.Interface) (reenqueued, skipped, failed int, err error) {
	_, _, deadLettered, err := wq.Enumerate(ctx)
	if err != nil {
		return 0, 0, 0, err
	}

	if len(deadLettered) == 0 {
		clog.InfoContext(ctx, "No dead-lettered keys found")
		return 0, 0, 0, nil
	}

	clog.InfoContextf(ctx, "Found %d dead-lettered keys", len(deadLettered))

	for _, dlk := range deadLettered {
		key := dlk.Name()

		// Enumerate's queued keys cannot answer this: they leave out a key
		// waiting in a backoff and stop at the queue's limit.
		state, err := wq.Get(ctx, key)
		switch {
		case status.Code(err) == codes.NotFound:
			clog.InfoContextf(ctx, "Skipping key %s: completed since it was listed", key)
			skipped++
			continue
		case err != nil:
			// The key may be queued or in progress, so it is not queued here.
			clog.ErrorContextf(ctx, "Failed to get state of key %s: %v", key, err)
			failed++
			continue
		case state.GetStatus() != workqueue.KeyState_DEAD_LETTER:
			clog.InfoContextf(ctx, "Skipping key %s: status is %v", key, state.GetStatus())
			skipped++
			continue
		}

		clog.InfoContextf(ctx, "Reenqueuing key: %s (failed at: %v, attempts: %d)",
			key, dlk.GetFailedTime(), dlk.GetAttempts())

		if err := wq.Queue(ctx, key, workqueue.Options{Priority: dlk.Priority()}); err != nil {
			clog.ErrorContextf(ctx, "Failed to reenqueue key %s: %v", key, err)
			failed++
			continue
		}

		reenqueued++
		clog.InfoContextf(ctx, "Successfully reenqueued key: %s", key)
	}

	clog.InfoContextf(ctx, "Reenqueue complete: %d reenqueued, %d skipped, %d failed", reenqueued, skipped, failed)
	return reenqueued, skipped, failed, nil
}
