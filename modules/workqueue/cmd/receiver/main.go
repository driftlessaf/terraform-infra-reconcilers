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

	"chainguard.dev/go-grpc-kit/pkg/duplex"
	"cloud.google.com/go/storage"
	"github.com/chainguard-dev/clog"
	_ "github.com/chainguard-dev/clog/gcp/init"
	"github.com/sethvargo/go-envconfig"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	"chainguard.dev/driftlessaf/workqueue"
	"chainguard.dev/driftlessaf/workqueue/gcs"
	"chainguard.dev/terraform-infra-reconcilers/modules/workqueue/enqueue"
	"github.com/chainguard-dev/terraform-infra-common/pkg/httpmetrics"
)

var env = envconfig.MustProcess(context.Background(), &struct {
	Port        int    `env:"PORT, required"`
	Concurrency int    `env:"WORKQUEUE_CONCURRENCY, required"`
	Mode        string `env:"WORKQUEUE_MODE, required"`
	Bucket      string `env:"WORKQUEUE_BUCKET"`
}{})

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	go httpmetrics.ServeMetrics()

	d := duplex.New(
		env.Port,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)

	var wq workqueue.Interface

	switch env.Mode {
	case "gcs":
		cl, err := storage.NewClient(ctx)
		if err != nil {
			clog.FatalContextf(ctx, "Failed to create client: %v", err)
		}

		wq = gcs.NewWorkQueue(cl.Bucket(env.Bucket), env.Concurrency)

	default:
		clog.FatalContextf(ctx, "Unsupported mode: %q", env.Mode)
	}

	workqueue.RegisterWorkqueueServiceServer(d.Server, enqueue.NewServer(wq))
	if err := d.ListenAndServe(ctx); err != nil {
		clog.FatalContextf(ctx, "ListenAndServe() = %v", err)
	}
}
