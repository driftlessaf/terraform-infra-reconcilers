# terraform-infra-reconcilers

Terraform modules for deploying reconcilers using DriftlessAF.

## Overview

This module provides Terraform infrastructure for building reconciliation systems that process work items asynchronously using a distributed workqueue backed by GCS.

## Modules

### workqueue

Core workqueue infrastructure providing:
- Multi-regional GCS-backed work queue
- Dispatcher for processing queued items
- Receiver for accepting new work items
- Reenqueue job for handling dead-lettered items

### github-path-reconciler

Path-based reconciliation triggered by GitHub push events:
- Push listener that receives GitHub webhook events
- Resync cron job for periodic reconciliation
- Pattern-based path matching for selective processing

### cloudevents-workqueue

CloudEvents to workqueue bridge:
- Receives CloudEvents and extracts workqueue keys
- Queues work items based on event extensions

### regional-go-reconciler

Combines workqueue with regional Go service deployment for complete reconciler infrastructure.

### dashboard/reconciler

Monitoring dashboard for reconciler services.

### dashboard/workqueue

Monitoring dashboard for workqueue metrics.

## Usage

### Terraform Registry

```hcl
module "workqueue" {
  source  = "driftlessaf/reconcilers/infra//modules/workqueue"
  version = "~> 1.0"
  # ...
}

module "github-path-reconciler" {
  source  = "driftlessaf/reconcilers/infra//modules/github-path-reconciler"
  version = "~> 1.0"
  # ...
}

module "cloudevents-workqueue" {
  source  = "driftlessaf/reconcilers/infra//modules/cloudevents-workqueue"
  version = "~> 1.0"
  # ...
}
```

## Go Code

The modules include embedded Go code for the reconciler services. The Go code imports from `driftlessaf/go-driftlessaf` for workqueue and githubreconciler packages.

## License

Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
