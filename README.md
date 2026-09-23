# Terraform infrastructure reconcilers

This directory contains Terraform modules for deploying reconciliation systems on Google Cloud with [DriftlessAF](https://github.com/driftlessaf/go-driftlessaf).

A reconciler receives a key for a resource, reads its current state, compares that state with the desired state, and applies any needed changes. Because the workqueue stores keys, repeated notifications for the same resource can be handled by reconciling its latest state. Reconciler actions should be safe to repeat.

## Choose a module

The [module catalog](./MODULES.md) lists the available modules and how they fit together. Common starting points include:

| Module | Purpose |
| --- | --- |
| [`regional-go-reconciler`](./modules/regional-go-reconciler/) | Deploy a Go reconciler with a workqueue and regional service. |
| [`github-path-reconciler`](./modules/github-path-reconciler/) | Reconcile repository paths after GitHub events and scheduled resyncs. |
| [`cloudevents-workqueue`](./modules/cloudevents-workqueue/) | Enqueue work from filtered CloudEvents. |
| [`workqueue`](./modules/workqueue/) | Deploy queue infrastructure for a separately managed reconciler. |
| [`dashboard/workqueue`](./modules/dashboard/workqueue/) | Display workqueue metrics in Cloud Monitoring. |

Start with each module's `variables.tf` and README for its current inputs. For example, `regions` is a map of region names to network and subnet settings in the reconciler and workqueue modules. The GitHub path reconciler configures repositories through its `repos` input.

## Workqueue behavior

The workqueue receives keys and stores them in Cloud Storage. Dispatchers claim eligible keys and call the reconciler. Failed work can be retried and, after the configured retry limit, moved to the dead letter queue. The `max-retry` input controls that limit; a value of `0` allows unlimited retries.

The standalone `workqueue` module requires `scope = "global"` and stores queue data in a multi-regional Cloud Storage bucket. Set `multi_regional_location` to `US`, `EU`, or `ASIA` as appropriate for the deployment.

See the [coding agent guidance](./AGENTS.md) and [module catalog](./MODULES.md) before adding a reconciler or changing queue behavior.
