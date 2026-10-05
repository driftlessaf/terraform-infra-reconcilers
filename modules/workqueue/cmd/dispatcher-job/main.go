/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

// dispatcher-job claims workqueue keys, reconciles them through a reconciler
// sidecar container, and exits when the last one finishes. It is designed to
// run as a Cloud Run Job, replacing the long-running dispatcher service for
// workloads whose reconciliation exceeds Cloud Run's request timeout. By
// default it makes a single dispatch pass at startup; with
// WORKQUEUE_CLAIM_WINDOW set it keeps claiming into its free slots for that
// long (see claimLoop).
package main

import (
	"context"
	"errors"
	"math/rand/v2"
	"os"
	"os/signal"
	"sync"
	"sync/atomic"
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
	// scrapeWait bounds how long the job stays alive waiting to be scraped. The
	// otel sidecar in regional-go-cron scrapes every 10s (see its
	// otel-config/config.yaml), but every execution starts a fresh sidecar, so
	// the first scrape lands one interval after the collector finishes booting,
	// not after the job does. await returns as soon as it is scraped, so a bound
	// well above one interval costs nothing except when no scrape ever arrives.
	scrapeWait = 30 * time.Second
	// scrapeInterval is the otel sidecar's scrape_interval, also from
	// regional-go-cron's otel config. The scrape await observes is the
	// dispatcher's own; the reconciler sidecar is a separate target the
	// collector scrapes at its own offset. Every target is scraped once per
	// interval, so a full interval after the dispatcher's first post-dispatch
	// scrape, every target has been scraped since the dispatch finished.
	scrapeInterval = 10 * time.Second
	// scrapeTimeout bounds how long a scrape the collector has started can take
	// to finish. regional-go-cron's otel config sets no scrape_timeout, so it
	// is Prometheus's default, which is also 10s. A scrape that starts at the
	// very end of scrapeInterval may take this long to complete before its
	// batch can begin flushing.
	scrapeTimeout = 10 * time.Second
	// batchFlush is the collector's batch processor timeout, also from
	// regional-go-cron's otel config. Staying alive that much longer after the
	// scrape lets the batch reach GMP before Cloud Run tears the sidecar down.
	batchFlush = 5 * time.Second
	// deadlineMargin is how long before the job's timeout every reconcile must
	// have returned. The dispatcher records a timed-out reconcile as a failed
	// attempt only while its own context is alive; Cloud Run's SIGTERM at the
	// timeout would turn it into a shutdown, which requeues without spending an
	// attempt, so a reconcile that always runs out the clock would loop forever
	// instead of dead-lettering. The margin covers that requeue write and the
	// metrics hold after it (scrapeWait plus a scrape, its timeout, and the
	// batch flush).
	deadlineMargin = 2 * time.Minute
)

// envConfig is read in main rather than at package scope so that tests of this
// package's helpers don't have to satisfy the job's required variables.
type envConfig struct {
	Concurrency                   int           `env:"WORKQUEUE_CONCURRENCY,required"`
	OwnerConcurrency              int           `env:"WORKQUEUE_OWNER_CONCURRENCY,default=0"`
	CandidateWindowFactor         int           `env:"WORKQUEUE_CANDIDATE_WINDOW_FACTOR,default=0"`
	BatchSize                     int           `env:"WORKQUEUE_BATCH_SIZE,required"`
	Mode                          string        `env:"WORKQUEUE_MODE,required"`
	Bucket                        string        `env:"WORKQUEUE_BUCKET"`
	Target                        string        `env:"WORKQUEUE_TARGET,required"`
	MaxRetry                      int           `env:"WORKQUEUE_MAX_RETRY,default=0"`
	ScheduledWaitWarningThreshold time.Duration `env:"WORKQUEUE_SCHEDULED_WAIT_WARNING_THRESHOLD,default=0s"`
	// ClaimWindow is how long after startup the job keeps claiming keys
	// into its free slots, every ClaimPoll (jittered), while it still has
	// work in flight. Zero makes the single pass at startup the only one.
	ClaimWindow time.Duration `env:"WORKQUEUE_CLAIM_WINDOW,default=0s"`
	ClaimPoll   time.Duration `env:"WORKQUEUE_CLAIM_POLL,default=10s"`
	// JobTimeout is the job execution's timeout. When set, every reconcile
	// must return deadlineMargin before it (see withDeadline). Zero leaves
	// reconciles unbounded.
	JobTimeout time.Duration `env:"WORKQUEUE_JOB_TIMEOUT,default=0s"`

	ErrorEventIngressURI string `env:"ERROR_EVENT_INGRESS_URI"`
	WorkqueueName        string `env:"WORKQUEUE_NAME"`
	// Identity is recorded as the owner of keys this job claims. The module sets
	// it to the job's region.
	Identity string `env:"WORKQUEUE_OWNER"`
	// ReportEvery is how often an idle job with a dead-letter backlog pays to
	// publish the gauge (see shouldReport). It must stay well under the
	// alert's one-hour auto_close. The gate passes only executions that run in
	// a wall-clock minute divisible by it, which executions on a sparser
	// schedule than every minute can miss every time.
	ReportEvery time.Duration `env:"WORKQUEUE_REPORT_EVERY,default=5m"`
}

func main() {
	// Cloud Run's timeout clock runs from about when this process starts, so
	// the reconcile deadline is measured from here; deadlineMargin also absorbs
	// the container start before it.
	started := time.Now()
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
	if env.ReportEvery < time.Minute || env.ReportEvery%time.Minute != 0 {
		clog.FatalContextf(ctx, "WORKQUEUE_REPORT_EVERY must be a positive whole number of minutes, got %s", env.ReportEvery)
	}
	if env.ClaimWindow > 0 && env.ClaimPoll <= 0 {
		clog.FatalContextf(ctx, "WORKQUEUE_CLAIM_POLL must be positive with a claim window, got %s", env.ClaimPoll)
	}
	if env.JobTimeout > 0 && env.JobTimeout <= deadlineMargin {
		clog.FatalContextf(ctx, "WORKQUEUE_JOB_TIMEOUT must exceed %s, got %s", deadlineMargin, env.JobTimeout)
	}
	// A key claimed after the reconcile deadline would fail at once and spend
	// an attempt without ever running.
	if env.JobTimeout > 0 && env.ClaimWindow >= env.JobTimeout-deadlineMargin {
		clog.FatalContextf(ctx, "WORKQUEUE_CLAIM_WINDOW (%s) must end before the reconcile deadline, %s before WORKQUEUE_JOB_TIMEOUT (%s)", env.ClaimWindow, deadlineMargin, env.JobTimeout)
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

	var processed, inUse atomic.Int64
	claims := &reservingQueue{Interface: wq, inUse: &inUse, first: firstClaimLogger(ctx, time.Now())}
	reconcile := dispatcher.ServiceCallback(client)
	if env.JobTimeout > 0 {
		reconcile = withDeadline(reconcile, started.Add(env.JobTimeout-deadlineMargin))
	}
	callback := releaseSlot(countCalls(reconcile, &processed), &inUse)
	opts := []dispatcher.Option{
		dispatcher.WithOwnerConcurrency(env.OwnerConcurrency),
		dispatcher.WithCandidateWindowFactor(env.CandidateWindowFactor),
		dispatcher.WithErrorIngressURI(ctx, env.ErrorEventIngressURI, env.WorkqueueName),
	}
	pass := func(ctx context.Context, batch int) dispatcher.Future {
		return dispatcher.HandleAsync(ctx, claims, env.Concurrency, batch, callback, env.MaxRetry, opts...)
	}
	if err := claimLoop(ctx, env.BatchSize, env.ClaimWindow, env.ClaimPoll, &inUse, &processed, pass); err != nil {
		clog.FatalContextf(ctx, "dispatch: %v", err)
	}

	switch {
	case processed.Load() > 0:
		// Every execution is a fresh process, and the collector exports nothing a
		// target observed after its last scrape. A reconcile records its final
		// observations (a run's duration, a key's outcome) just before its
		// callback returns, which is just before this process exits and Cloud
		// Run tears down the sidecars with it. Without a hold those are lost
		// outright, not delayed. So an execution that did any work stays alive
		// until every target — the reconciler, not just this dispatcher — has
		// been scraped since the dispatch finished, that scrape has completed,
		// and the batch has flushed. Idle executions, the common case on a
		// quiet queue, skip this.
		scraped.await(ctx, scrapeWait, scrapeInterval+scrapeTimeout+batchFlush)
	case shouldReport(time.Now(), env.ReportEvery) && deadLettered(ctx, prometheus.DefaultGatherer) > 0:
		// An idle iteration finishes in well under a scrape interval, so exiting
		// here means the gauges it just set are never exported. A drained queue
		// can afford that: the dead-letter alert's auto_close reads the resulting
		// silence as "nothing to report". A non-empty dead-letter queue cannot —
		// without a sample the alert closes and re-pages on the next stray
		// scrape, over and over, for a backlog that never changed. So hold the
		// process open for a scrape exactly when there is a backlog to report, on
		// a cadence the alert's auto_close window absorbs. Only this
		// dispatcher's own gauge matters here, so its own scrape suffices.
		scraped.await(ctx, scrapeWait, batchFlush)
	}
}

// withDeadline wraps a dispatch callback so the reconcile it runs returns by
// deadline. A reconcile still running then fails with the context's deadline
// error while the dispatcher is alive, so the dispatcher spends one of the key's
// attempts on it and, once they run out, dead-letters it.
func withDeadline(f dispatcher.Callback, deadline time.Time) dispatcher.Callback {
	return func(ctx context.Context, key string, opts workqueue.Options) error {
		ctx, cancel := context.WithDeadline(ctx, deadline)
		defer cancel()
		return f(ctx, key, opts)
	}
}

// countCalls wraps a dispatch callback to count the keys it is handed, so main
// can tell an execution that did work from an idle one.
func countCalls(f dispatcher.Callback, n *atomic.Int64) dispatcher.Callback {
	return func(ctx context.Context, key string, opts workqueue.Options) error {
		n.Add(1)
		return f(ctx, key, opts)
	}
}

// passFunc runs one dispatch pass that claims at most batch keys and returns
// the future that joins them: dispatcher.HandleAsync, bound to this job's
// queue and callback.
type passFunc func(ctx context.Context, batch int) dispatcher.Future

// claimLoop runs the job's dispatch passes and returns once every key they
// claimed has finished. The first pass runs at once and claims up to
// batchSize keys. With a window, the job then keeps claiming until window has
// passed since it started: every poll (jittered by up to half either way) a
// pass claims into whatever slots finished keys freed, and a job whose keys
// have all finished makes one more pass before it exits. A key queued while
// the job runs then waits for the next poll rather than for the next
// execution. Cloud Run takes minutes to start an execution, and starts
// several at once, so a job that claims only at startup leaves a run queued
// for minutes behind jobs with free slots.
//
// The loop claims only while the job has work: a job whose last pass
// claimed nothing and has nothing in flight returns, as a single-pass job
// does, rather than stay alive — and billed — to poll an empty queue. A lost
// claim (a sibling won the key) costs its slot for one poll instead of for
// the job's life, and the jitter spreads siblings that started in the same
// second across the poll. A pass's error is logged and claiming goes on, so
// one failed enumeration does not strand the keys already in flight; every
// error is returned once the keys have finished.
//
// inUse counts this job's own slots in use: a claim holds one from the
// moment its Start begins, through the callback, until the callback returns
// (reservingQueue, releaseSlot), so a claim still completing its Start is
// never offered to a later pass. claimed counts every key handed to a
// callback (countCalls).
func claimLoop(ctx context.Context, batchSize int, window, poll time.Duration, inUse, claimed *atomic.Int64, pass passFunc) error {
	started := time.Now()
	var (
		mu   sync.Mutex
		errs []error
		wg   sync.WaitGroup
	)
	// Every pass signals done once; the loop and the drain below receive
	// exactly that many.
	done := make(chan struct{})
	outstanding := 0
	launch := func(batch int) {
		outstanding++
		fut := pass(ctx, batch)
		wg.Go(func() {
			if err := fut(); err != nil {
				clog.WarnContextf(ctx, "dispatch pass: %v", err)
				mu.Lock()
				errs = append(errs, err)
				mu.Unlock()
			}
			done <- struct{}{}
		})
	}
	passes := 1
	launch(batchSize)
	deadline := started.Add(window)
	// claimedAtDry is the claim count when the job last ran out of work;
	// running out again with no claim since means the queue has nothing.
	var claimedAtDry int64
loop:
	for window > 0 {
		remaining := time.Until(deadline)
		if remaining <= 0 {
			break
		}
		t := time.NewTimer(min(jittered(poll), remaining))
		select {
		case <-ctx.Done():
			t.Stop()
			break loop
		case <-done:
			t.Stop()
			outstanding--
			if outstanding > 0 {
				continue
			}
			n := claimed.Load()
			if n == claimedAtDry {
				break loop
			}
			claimedAtDry = n
			passes++
			launch(batchSize)
		case <-t.C:
			if free := batchSize - int(inUse.Load()); free > 0 {
				passes++
				launch(free)
			}
		}
	}
	go func() {
		for range outstanding {
			<-done
		}
	}()
	wg.Wait()
	clog.InfoContextf(ctx, "dispatcher-job: %d key(s) claimed in %d dispatch pass(es) over %s (claim window %s)", claimed.Load(), passes, time.Since(started).Round(time.Millisecond), window)
	return errors.Join(errs...)
}

// jittered spreads d uniformly over [d/2, 3d/2).
func jittered(d time.Duration) time.Duration {
	if d <= 1 {
		return d
	}
	return d/2 + rand.N(d) //nolint:gosec // G404: jitter, not security-sensitive
}

// reservingQueue is the job's queue with its claims counted against the
// job's own capacity. The dispatcher starts each claim on a goroutine of its
// own, and a claim whose in-progress copy has landed can still be deleting
// its queued object when the next poll counts free slots; counting only
// running callbacks would offer that slot again, and the job's sidecar,
// sized for batchSize runs, would carry more. A claim takes a slot of inUse
// when its Start begins and gives it back if the Start fails; a started
// key's slot is released when its callback returns (releaseSlot). first is
// told of the first key the job claims.
type reservingQueue struct {
	workqueue.Interface
	inUse *atomic.Int64
	first func(key string)
	once  sync.Once
}

var (
	_ workqueue.Interface     = (*reservingQueue)(nil)
	_ workqueue.CapacityAware = (*reservingQueue)(nil)
)

func (q *reservingQueue) Enumerate(ctx context.Context) ([]workqueue.ObservedInProgressKey, []workqueue.QueuedKey, []workqueue.DeadLetteredKey, error) {
	wip, next, dead, err := q.Interface.Enumerate(ctx)
	return wip, q.reserving(next), dead, err
}

// EnumerateWithCapacity keeps the queue's capacity-aware listing when it
// has one, and is a plain Enumerate otherwise.
func (q *reservingQueue) EnumerateWithCapacity(ctx context.Context, totalCapacity int) ([]workqueue.ObservedInProgressKey, []workqueue.QueuedKey, []workqueue.DeadLetteredKey, error) {
	bounded, ok := q.Interface.(workqueue.CapacityAware)
	if !ok {
		return q.Enumerate(ctx)
	}
	wip, next, dead, err := bounded.EnumerateWithCapacity(ctx, totalCapacity)
	return wip, q.reserving(next), dead, err
}

func (q *reservingQueue) reserving(next []workqueue.QueuedKey) []workqueue.QueuedKey {
	out := make([]workqueue.QueuedKey, 0, len(next))
	for _, k := range next {
		out = append(out, reservingKey{QueuedKey: k, q: q})
	}
	return out
}

// reservingKey is a queued key whose Start holds a slot of its queue's
// inUse while it runs and, when it succeeds, until the key's callback
// returns.
type reservingKey struct {
	workqueue.QueuedKey
	q *reservingQueue
}

func (k reservingKey) Start(ctx context.Context) (workqueue.OwnedInProgressKey, error) {
	k.q.inUse.Add(1)
	oip, err := k.QueuedKey.Start(ctx)
	if err != nil {
		k.q.inUse.Add(-1)
		return nil, err
	}
	k.q.once.Do(func() { k.q.first(k.Name()) })
	return oip, nil
}

// releaseSlot wraps a dispatch callback to give back the slot its key's
// Start took (reservingKey) once the callback returns.
func releaseSlot(f dispatcher.Callback, inUse *atomic.Int64) dispatcher.Callback {
	return func(ctx context.Context, key string, opts workqueue.Options) error {
		defer inUse.Add(-1)
		return f(ctx, key, opts)
	}
}

// firstClaimLogger logs, once, how long after the job started it claimed
// its first key: with the execution's creation time, what a run waits to be
// picked up.
func firstClaimLogger(ctx context.Context, started time.Time) func(key string) {
	return func(key string) {
		clog.InfoContextf(ctx, "dispatcher-job: first key %q claimed %s after startup", key, time.Since(started).Round(time.Millisecond))
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

// await blocks until the metrics endpoint is scraped and then for settle more,
// long enough for the collector to scrape any other targets and forward the
// batch, or until wait elapses without a scrape.
func (s *scrapeSignal) await(ctx context.Context, wait, settle time.Duration) {
	// Discard any scrape that predates the end of the dispatch iteration —
	// including the Gather that read the dead-letter gauge.
	select {
	case <-s.ch:
	default:
	}

	t := time.NewTimer(wait)
	defer t.Stop()
	select {
	case <-s.ch:
	case <-t.C:
		clog.WarnContextf(ctx, "exiting after %s without a metrics scrape; this execution's final metrics were not exported", wait)
		return
	case <-ctx.Done():
		return
	}

	f := time.NewTimer(settle)
	defer f.Stop()
	select {
	case <-f.C:
	case <-ctx.Done():
	}
}
