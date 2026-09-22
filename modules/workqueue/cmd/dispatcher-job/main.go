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
	"time"

	"cloud.google.com/go/storage"
	"github.com/chainguard-dev/clog"
	_ "github.com/chainguard-dev/clog/gcp/init"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/sethvargo/go-envconfig"

	"chainguard.dev/driftlessaf/workqueue"
	"chainguard.dev/driftlessaf/workqueue/dispatcher"
	"chainguard.dev/driftlessaf/workqueue/gcs"
	"github.com/chainguard-dev/terraform-infra-common/pkg/httpmetrics"
)

const (
	// reportEvery is how often a job with a backlog pays to publish the gauge.
	// The alert's auto_close is an hour, so the series only has to carry a
	// sample more often than that; five minutes leaves room to miss eleven
	// consecutive reports before the incident falsely clears. Holding on every
	// tick instead would buy a minute of detection latency for roughly five
	// times the cost, and the cost is not the dispatcher's — the hold keeps the
	// whole execution alive, reconciler sidecars included, which on a queue like
	// axlotl-decant is another 4 vCPU and 8GiB.
	reportEvery = 5 * time.Minute
	// scrapeWait bounds how long the job stays alive waiting to be scraped. The
	// otel sidecar in regional-go-cron scrapes every 10s (see its
	// otel-config/config.yaml), but every execution starts a fresh sidecar, so
	// the first scrape lands one interval after the collector finishes booting,
	// not after the job does. await returns as soon as it is scraped, so a bound
	// well above one interval costs nothing except when no scrape ever arrives.
	scrapeWait = 30 * time.Second
	// batchFlush is the collector's batch processor timeout, also from
	// regional-go-cron's otel config. Staying alive that much longer after the
	// scrape lets the batch reach GMP before Cloud Run tears the sidecar down.
	batchFlush = 5 * time.Second
)

// envConfig is read in main rather than at package scope so that tests of this
// package's helpers don't have to satisfy the job's required variables.
type envConfig struct {
	Concurrency                   int           `env:"WORKQUEUE_CONCURRENCY,required"`
	OwnerConcurrency              int           `env:"WORKQUEUE_OWNER_CONCURRENCY,default=0"`
	BatchSize                     int           `env:"WORKQUEUE_BATCH_SIZE,required"`
	Mode                          string        `env:"WORKQUEUE_MODE,required"`
	Bucket                        string        `env:"WORKQUEUE_BUCKET"`
	Target                        string        `env:"WORKQUEUE_TARGET,required"`
	MaxRetry                      int           `env:"WORKQUEUE_MAX_RETRY,default=0"`
	ScheduledWaitWarningThreshold time.Duration `env:"WORKQUEUE_SCHEDULED_WAIT_WARNING_THRESHOLD,default=0s"`

	ErrorEventIngressURI string `env:"ERROR_EVENT_INGRESS_URI"`
	WorkqueueName        string `env:"WORKQUEUE_NAME"`
	// Identity is recorded as the owner of keys this job claims. The module sets
	// it to the job's region.
	Identity string `env:"WORKQUEUE_OWNER"`
}

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	env := envconfig.MustProcess(ctx, &envConfig{})

	// `required` rejects an unset variable, not a set-but-useless one. An
	// explicit WORKQUEUE_CONCURRENCY=0 or WORKQUEUE_BATCH_SIZE=0 decodes fine and
	// then dispatches nothing at all, so the queue stalls while the job keeps
	// exiting 0 every minute and nothing pages. Neither is a legitimate
	// configured value, so fail loud.
	if env.Concurrency <= 0 {
		clog.FatalContextf(ctx, "WORKQUEUE_CONCURRENCY must be positive, got %d", env.Concurrency)
	}
	if env.BatchSize <= 0 {
		clog.FatalContextf(ctx, "WORKQUEUE_BATCH_SIZE must be positive, got %d", env.BatchSize)
	}

	scraped := newScrapeSignal()
	prometheus.MustRegister(scraped)
	go httpmetrics.ServeMetrics()

	var wq workqueue.Interface
	switch env.Mode {
	case "gcs":
		cl, err := storage.NewClient(ctx)
		if err != nil {
			clog.FatalContextf(ctx, "Failed to create storage client: %v", err)
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
		clog.FatalContextf(ctx, "failed to create workqueue client: %v", err)
	}
	defer client.Close()

	if err := dispatcher.HandleAsync(ctx, wq, env.Concurrency, env.BatchSize,
		dispatcher.ServiceCallback(client), env.MaxRetry,
		dispatcher.WithOwnerConcurrency(env.OwnerConcurrency),
		dispatcher.WithErrorIngressURI(ctx, env.ErrorEventIngressURI, env.WorkqueueName),
	)(); err != nil {
		clog.FatalContextf(ctx, "dispatch: %v", err)
	}

	// An idle iteration finishes in well under a scrape interval, so exiting
	// here means the gauges it just set are never exported. A drained queue can
	// afford that: the dead-letter alert's auto_close reads the resulting
	// silence as "nothing to report". A non-empty dead-letter queue cannot —
	// without a sample the alert closes and re-pages on the next stray scrape,
	// over and over, for a backlog that never changed. So hold the process open
	// for a scrape exactly when there is a backlog to report, on a cadence the
	// alert's auto_close window absorbs.
	if shouldReport(time.Now(), reportEvery) && deadLettered(ctx, prometheus.DefaultGatherer) > 0 {
		scraped.await(ctx, scrapeWait, batchFlush)
	}
}

// shouldReport gates the hold to a wall-clock cadence. Anchoring on the clock
// rather than on a counter means nothing has to survive between executions —
// each one is a fresh process — and every region lands on the same ticks, which
// the alert reduces across with REDUCE_MAX anyway. A pass that outruns its tick
// needs no gate: a job that stays alive for minutes is scraped for free.
func shouldReport(now time.Time, every time.Duration) bool {
	return now.Truncate(time.Minute).UnixNano()%int64(every) == 0
}

// deadLettered reads back the workqueue_dead_lettered_keys gauge the dispatch
// iteration just set, summed across queues. Reading the registry rather than
// re-enumerating the bucket costs nothing and reports exactly what a scrape
// would export.
func deadLettered(ctx context.Context, g prometheus.Gatherer) float64 {
	mfs, err := g.Gather()
	if err != nil {
		clog.WarnContextf(ctx, "gathering metrics: %v", err)
	}
	var total float64
	for _, mf := range mfs {
		if mf.GetName() != "workqueue_dead_lettered_keys" {
			continue
		}
		for _, m := range mf.GetMetric() {
			total += m.GetGauge().GetValue()
		}
	}
	return total
}

// scrapeSignal is a collector that exports nothing and exists only to observe
// scrapes: the default gatherer calls Collect once per /metrics request.
type scrapeSignal struct {
	ch chan struct{}
}

func newScrapeSignal() *scrapeSignal {
	return &scrapeSignal{ch: make(chan struct{}, 1)}
}

func (s *scrapeSignal) Describe(chan<- *prometheus.Desc) {}

func (s *scrapeSignal) Collect(chan<- prometheus.Metric) {
	select {
	case s.ch <- struct{}{}:
	default:
	}
}

// await blocks until the metrics endpoint is scraped and the collector has had
// flush long to forward the batch, or until wait elapses without a scrape.
func (s *scrapeSignal) await(ctx context.Context, wait, flush time.Duration) {
	// Discard any scrape that predates the dispatch iteration — including the
	// Gather that read the dead-letter gauge.
	select {
	case <-s.ch:
	default:
	}

	t := time.NewTimer(wait)
	defer t.Stop()
	select {
	case <-s.ch:
	case <-t.C:
		clog.WarnContextf(ctx, "exiting after %s without a metrics scrape; dead-letter gauge not exported", wait)
		return
	case <-ctx.Done():
		return
	}

	f := time.NewTimer(flush)
	defer f.Stop()
	select {
	case <-f.C:
	case <-ctx.Done():
	}
}
