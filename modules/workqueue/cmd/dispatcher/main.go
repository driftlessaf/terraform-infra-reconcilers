/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"cloud.google.com/go/storage"
	"github.com/chainguard-dev/clog"
	_ "github.com/chainguard-dev/clog/gcp/init"
	"github.com/sethvargo/go-envconfig"

	"chainguard.dev/driftlessaf/workqueue"
	"chainguard.dev/driftlessaf/workqueue/dispatcher"
	"chainguard.dev/driftlessaf/workqueue/gcs"
	"github.com/chainguard-dev/clog/gcp"
	"github.com/chainguard-dev/terraform-infra-common/pkg/httpmetrics"
)

var env = envconfig.MustProcess(context.Background(), &struct {
	Port             int    `env:"PORT,required"`
	Concurrency      int    `env:"WORKQUEUE_CONCURRENCY,required"`
	OwnerConcurrency int    `env:"WORKQUEUE_OWNER_CONCURRENCY,default=0"`
	BatchSize        int    `env:"WORKQUEUE_BATCH_SIZE,required"`
	Mode             string `env:"WORKQUEUE_MODE,required"`
	Bucket           string `env:"WORKQUEUE_BUCKET"`
	Target           string `env:"WORKQUEUE_TARGET,required"`
	MaxRetry         int    `env:"WORKQUEUE_MAX_RETRY,default=0"` // 0 means unlimited retries
	// Identity is recorded as the owner of keys this dispatcher claims. The
	// module sets it to the dispatcher's region.
	Identity string `env:"WORKQUEUE_OWNER"`

	// Optional: emit dispatch errors as CloudEvents.
	// When ErrorEventIngressURI is empty, error events are disabled.
	ErrorEventIngressURI string `env:"ERROR_EVENT_INGRESS_URI"`
	WorkqueueName        string `env:"WORKQUEUE_NAME"`
}{})

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	go httpmetrics.ServeMetrics()

	var wq workqueue.Interface
	switch env.Mode {
	case "gcs":
		cl, err := storage.NewClient(ctx)
		if err != nil {
			clog.FatalContextf(ctx, "Failed to create client: %v", err)
		}
		wq = gcs.NewWorkQueue(cl.Bucket(env.Bucket), env.Concurrency, gcs.WithIdentity(env.Identity))

		// Launch a go routine in the background to periodically call Enumerate
		// to ensure that each replica surfaces the latest and greatest metrics
		// even if the worker isn't being invoked for fresh work.
		go func() {
			tick := time.NewTicker(30 * time.Second)
			for {
				select {
				case <-ctx.Done():
					return
				case <-tick.C:
					_, _, _, err := wq.Enumerate(ctx)
					if err != nil {
						clog.ErrorContextf(ctx, "Failed to enumerate: %v", err)
					}
				}
			}
		}()

	default:
		clog.FatalContextf(ctx, "Unsupported mode: %q", env.Mode)
	}

	client, err := workqueue.NewWorkqueueClient(ctx, env.Target)
	if err != nil {
		clog.FatalContextf(ctx, "failed to create client: %v", err)
	}
	defer client.Close()

	protocols := new(http.Protocols)
	protocols.SetHTTP1(true)
	protocols.SetUnencryptedHTTP2(true)

	if err := (&http.Server{
		Addr: fmt.Sprintf(":%d", env.Port),
		Handler: gcp.WithCloudTraceContext(dispatcher.Handler(
			wq, env.Concurrency, env.BatchSize, dispatcher.ServiceCallback(client), env.MaxRetry,
			dispatcher.WithOwnerConcurrency(env.OwnerConcurrency),
			dispatcher.WithErrorIngressURI(ctx, env.ErrorEventIngressURI, env.WorkqueueName),
		)),
		ReadHeaderTimeout: 10 * time.Second,
		Protocols:         protocols,
	}).ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		clog.FatalContextf(ctx, "failed to start server: %v", err)
	}
}
