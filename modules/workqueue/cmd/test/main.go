/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"cloud.google.com/go/storage"
	"github.com/chainguard-dev/clog"

	"chainguard.dev/driftlessaf/workqueue"
	gcswq "chainguard.dev/driftlessaf/workqueue/gcs"
	"chainguard.dev/driftlessaf/workqueue/inmem"
)

func main() {
	// Parse command line flags
	t := flag.String("type", "gcs", "The type of workqueue to use.")
	bucketName := flag.String("bucket", "", "The name of the blob storage bucket")
	key := flag.String("key", "", "The workqueue key name")
	limit := flag.Int("limit", 5, "The concurrency limit")
	flag.Parse()

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	// Validate required flags
	if *bucketName == "" {
		clog.FatalContext(ctx, "Bucket name is required")
	}
	if *key == "" {
		clog.FatalContext(ctx, "Object key is required")
	}

	var wq workqueue.Interface

	switch *t {
	case "gcs":
		client, err := storage.NewClient(ctx)
		if err != nil {
			clog.FatalContextf(ctx, "Failed to create client: %v", err)
		}
		bh := client.Bucket(*bucketName)

		// Create a workqueue with the GCS bucket handle
		wq = gcswq.NewWorkQueue(bh, *limit)

	case "inmem":
		// Create a workqueue backed by memory.
		wq = inmem.NewWorkQueue(*limit)

	default:
		clog.FatalContextf(ctx, "Unknown workqueue type: %q", *t)
	}

	// Enqueue the key
	if err := wq.Queue(ctx, *key, workqueue.Options{}); err != nil {
		clog.FatalContextf(ctx, "Failed to enqueue key: %v", err)
	}
	fmt.Println("Key enqueued successfully")

	wip, qd, _, err := wq.Enumerate(ctx)
	if err != nil {
		clog.FatalContextf(ctx, "Failed to enumerate keys: %v", err)
	}

	wipKeys := make(map[string]struct{}, len(wip))
	for _, k := range wip {
		fmt.Printf("In progress key: %s (is orphan: %t)\n", k.Name(), k.IsOrphaned())
		wipKeys[k.Name()] = struct{}{}

		if k.IsOrphaned() {
			if err := k.Requeue(ctx); err != nil {
				clog.FatalContextf(ctx, "Failed to requeue orphaned key: %v", err)
			}
			fmt.Printf("Requeued orphaned key: %s\n", k.Name())
		}
	}

	for _, k := range qd {
		fmt.Printf("Queued key: %s\n", k.Name())
		if _, wip := wipKeys[k.Name()]; wip {
			fmt.Printf("Key is already in-progress: %s\n", k.Name())
			continue
		}

		oip, err := k.Start(ctx)
		if err != nil {
			clog.FatalContextf(ctx, "Failed to start key: %v", err)
		}
		fmt.Printf("Started key: %s\n", oip.Name())
		time.Sleep(2 * time.Second)
		if err := oip.Requeue(ctx); err != nil {
			clog.FatalContextf(ctx, "Failed to requeue key: %v", err)
		}
		fmt.Printf("Requeued key: %s\n", oip.Name())
	}
}
