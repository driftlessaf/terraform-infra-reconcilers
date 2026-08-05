/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"errors"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"chainguard.dev/go-grpc-kit/pkg/duplex"
	"github.com/chainguard-dev/clog"
	_ "github.com/chainguard-dev/clog/gcp/init"
	"github.com/sethvargo/go-envconfig"
	"golang.org/x/sync/errgroup"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	"chainguard.dev/driftlessaf/workqueue"
	"chainguard.dev/driftlessaf/workqueue/dispatcher"
	"chainguard.dev/driftlessaf/workqueue/inmem"
	"chainguard.dev/terraform-infra-reconcilers/modules/workqueue/enqueue"
	"github.com/chainguard-dev/terraform-infra-common/pkg/httpmetrics"
)

var env = envconfig.MustProcess(context.Background(), &struct {
	Port        int    `env:"PORT,required"`
	Concurrency int    `env:"WORKQUEUE_CONCURRENCY,required"`
	BatchSize   int    `env:"WORKQUEUE_BATCH_SIZE,required"`
	Target      string `env:"WORKQUEUE_TARGET,required"`
}{})

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	go httpmetrics.ServeMetrics()

	d := duplex.New(
		env.Port,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)

	client, err := workqueue.NewWorkqueueClient(ctx, env.Target)
	if err != nil {
		clog.FatalContextf(ctx, "failed to create client: %v", err)
	}
	defer client.Close()

	wq := inmem.NewWorkQueue(env.Concurrency)

	eg := errgroup.Group{}
	eg.Go(func() error {
		tick := time.NewTicker(100 * time.Millisecond)
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-tick.C:
				// Do this in a go routine, so it doesn't block the
				// dispatch loop.
				eg.Go(func() error {
					return dispatcher.Handle(context.WithoutCancel(ctx), wq,
						env.Concurrency, env.BatchSize, dispatcher.ServiceCallback(client))
				})
			}
		}
	})

	eg.Go(func() error {
		workqueue.RegisterWorkqueueServiceServer(d.Server, enqueue.NewServer(wq))
		if err := d.ListenAndServe(ctx); err != nil && !errors.Is(err, http.ErrServerClosed) {
			return err
		}
		return nil
	})

	if err := eg.Wait(); err != nil {
		clog.ErrorContextf(ctx, "Error group failed: %v", err)
	}
}
