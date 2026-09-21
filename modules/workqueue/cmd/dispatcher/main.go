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
	// Port is required; enforced in main().
	Port int `env:"PORT"`
	// Concurrency is required; enforced in main().
	Concurrency      int `env:"WORKQUEUE_CONCURRENCY"`
	OwnerConcurrency int `env:"WORKQUEUE_OWNER_CONCURRENCY,default=0"`
	// BatchSize is required; enforced in main().
	BatchSize int `env:"WORKQUEUE_BATCH_SIZE"`
	// Mode is required; enforced in main().
	Mode   string `env:"WORKQUEUE_MODE"`
	Bucket string `env:"WORKQUEUE_BUCKET"`
	// Target is required; enforced in main().
	Target string `env:"WORKQUEUE_TARGET"`
	// MaxRetry: 0 means unlimited retries.
	MaxRetry                      int           `env:"WORKQUEUE_MAX_RETRY,default=0"`
	ScheduledWaitWarningThreshold time.Duration `env:"WORKQUEUE_SCHEDULED_WAIT_WARNING_THRESHOLD,default=0s"`
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

	if env.Port == 0 {
		clog.FatalContextf(ctx, "PORT is required")
	}
	if env.Concurrency == 0 {
		clog.FatalContextf(ctx, "WORKQUEUE_CONCURRENCY is required")
	}
	if env.BatchSize == 0 {
		clog.FatalContextf(ctx, "WORKQUEUE_BATCH_SIZE is required")
	}
	if env.Mode == "" {
		clog.FatalContextf(ctx, "WORKQUEUE_MODE is required")
	}
	if env.Target == "" {
		clog.FatalContextf(ctx, "WORKQUEUE_TARGET is required")
	}

	go httpmetrics.ServeMetrics()

	var wq workqueue.Interface
	switch env.Mode {
	case "gcs":
		cl, err := storage.NewClient(ctx)
		if err != nil {
			clog.FatalContextf(ctx, "Failed to create client: %v", err)
		}
		wq = gcs.NewWorkQueue(cl.Bucket(env.Bucket), env.Concurrency,
			gcs.WithIdentity(env.Identity),
			gcs.WithScheduledWaitWarningThreshold(env.ScheduledWaitWarningThreshold),
		)

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
