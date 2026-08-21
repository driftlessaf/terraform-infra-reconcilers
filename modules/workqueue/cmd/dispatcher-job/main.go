/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

// dispatcher-job performs a single iteration of the workqueue dispatch loop and
// exits. It is designed to run as a Cloud Run Job alongside a reconciler sidecar
// container, replacing the long-running dispatcher service for workloads whose
// reconciliation exceeds Cloud Run's request timeout.
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

	"chainguard.dev/driftlessaf/workqueue"
	"chainguard.dev/driftlessaf/workqueue/dispatcher"
	"chainguard.dev/driftlessaf/workqueue/gcs"
	"github.com/chainguard-dev/terraform-infra-common/pkg/httpmetrics"
)

var env = envconfig.MustProcess(context.Background(), &struct {
	Concurrency int    `env:"WORKQUEUE_CONCURRENCY,required"`
	BatchSize   int    `env:"WORKQUEUE_BATCH_SIZE,required"`
	Mode        string `env:"WORKQUEUE_MODE,required"`
	Bucket      string `env:"WORKQUEUE_BUCKET"`
	Target      string `env:"WORKQUEUE_TARGET,required"`
	MaxRetry    int    `env:"WORKQUEUE_MAX_RETRY,default=0"`

	ErrorEventIngressURI string `env:"ERROR_EVENT_INGRESS_URI"`
	WorkqueueName        string `env:"WORKQUEUE_NAME"`
	// Owner is recorded on the keys this dispatcher claims (the module sets
	// it to the job's region), so in-progress work can be attributed.
	Owner string `env:"WORKQUEUE_OWNER"`
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
			clog.FatalContextf(ctx, "Failed to create storage client: %v", err)
		}
		wq = gcs.NewWorkQueue(cl.Bucket(env.Bucket), env.Concurrency, gcs.WithOwner(env.Owner))
	default:
		clog.FatalContextf(ctx, "Unsupported mode: %q", env.Mode)
	}

	client, err := workqueue.NewWorkqueueClient(ctx, env.Target)
	if err != nil {
		clog.FatalContextf(ctx, "failed to create workqueue client: %v", err)
	}
	defer client.Close()

	if err := dispatcher.HandleAsync(ctx, wq, env.Concurrency, env.BatchSize,
		dispatcher.ServiceCallback(client), env.MaxRetry,
		dispatcher.WithErrorIngressURI(ctx, env.ErrorEventIngressURI, env.WorkqueueName),
	)(); err != nil {
		clog.FatalContextf(ctx, "dispatch: %v", err)
	}
}
