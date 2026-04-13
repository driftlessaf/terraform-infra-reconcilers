# Module Catalog

Quick reference for all modules in this repository. See the [README](./README.md) for architecture overview and usage examples.

## Core Infrastructure

### [`workqueue`](./modules/workqueue/)

Distributed task queue built on GCS with controlled concurrency. Provisions a **receiver** (accepts work via gRPC), a **dispatcher** (delivers work to your reconciler), a GCS bucket for durable storage, Pub/Sub notifications for immediate dispatch, and cron-based polling as a fallback. Includes dead-letter queue handling and alerting.

Use this when you need a standalone workqueue decoupled from any specific reconciler deployment, or when composing your own reconciliation architecture from lower-level primitives.

### [`regional-go-reconciler`](./modules/regional-go-reconciler/)

All-in-one module that combines a workqueue with a multi-region Cloud Run Go service. Provisions the full stack: workqueue infrastructure, reconciler service built from source via ko, scaling configuration, and monitoring alerts.

Use this as the default starting point for any new reconciler. It handles the common case where you want a single workqueue feeding a single reconciler service and don't need to customize the wiring between them.

## Event Bridges

### [`cloudevents-workqueue`](./modules/cloudevents-workqueue/)

Subscribes to a CloudEvents broker, extracts a key from a specified event extension (e.g. `pullrequesturl`, `issueurl`), and enqueues it to a workqueue. Supports multiple event type filters combined with OR logic, configurable priority, and retry backoff.

Use this to connect any CloudEvents source to a workqueue. It is the standard bridge for event-driven reconciliation and is used internally by the meta-reconciler modules.

## GitHub Integration

### [`github-path-reconciler`](./modules/github-path-reconciler/)

Monitors specific file paths in a GitHub repository using regex patterns with capture groups. Combines two triggers: a **push listener** that reacts immediately to commits, and a **cron job** that performs periodic full-repository scans on a configurable schedule (1-744 hours). Uses Octo STS for GitHub API authentication.

Use this for GitOps workflows, config sync, or any scenario where you need to reconcile the state of specific files in a repository.

### [`github-metareconciler`](./modules/github-metareconciler/)

Opinionated composition of `regional-go-reconciler` + `cloudevents-workqueue` + dashboard, pre-wired for GitHub **issue and pull request** events. Subscribes to both event types with independent priority levels (PRs default higher) and routes them through a shared workqueue.

Use this when building a reconciler that processes GitHub issues and/or pull requests and you want the standard wiring done for you.

### [`github-metapathreconciler`](./modules/github-metapathreconciler/)

Opinionated composition of `github-path-reconciler` + `cloudevents-workqueue` + dashboard, pre-wired for both **path-based reconciliation** (push + cron) and **PR event processing**. PR events are routed to the same workqueue at a configurable priority.

Use this when your reconciler needs to react to both file-level changes (path patterns) and pull request events in the same GitHub repository.

## Linear Integration

### [`linear-metareconciler`](./modules/linear-metareconciler/)

Opinionated composition of `regional-go-reconciler` + `cloudevents-workqueue` + dashboard, pre-wired for Linear **issue and comment** events. Subscribes to both event types with independent priority and optional comment processing.

Use this when building a reconciler that automates workflows triggered by Linear issue or comment activity.

## AI and Machine Learning

### [`vertex-ai-vector-search`](./modules/vertex-ai-vector-search/)

Provision a Vertex AI Vector Search (Matching Engine) index with an endpoint, deployed index, and optional GCS bucket for durable embedding storage.

Use this when a service needs vector search infrastructure for RAG (Retrieval-Augmented Generation) or semantic similarity search. Call once per corpus — each corpus with a different embedding model requires its own index.

## Observability

### [`dashboard/workqueue`](./modules/dashboard/workqueue/)

Cloud Monitoring dashboard for a standalone workqueue. Displays queue depth, processing and wait latency, retry patterns, deduplication rates, and dead-letter queue status, with separate log panels for receiver and dispatcher services.

Use this when you deploy a `workqueue` module independently and want visibility into its health.

### [`dashboard/reconciler`](./modules/dashboard/reconciler/)

Cloud Monitoring dashboard for a complete reconciler system (workqueue + reconciler service). Includes everything from the workqueue dashboard plus gRPC statistics, error reporting, reconciler logs, and optional sections for GitHub API metrics and agent metrics.

Use this when you deploy a `regional-go-reconciler` or any meta-reconciler module and want unified monitoring across the full stack.
