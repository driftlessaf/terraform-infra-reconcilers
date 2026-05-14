# Workqueue Dashboard Module

This module creates a Cloud Monitoring dashboard for a workqueue implementation, providing visibility into queue metrics, processing latency, and system health.

## Usage

```hcl
module "workqueue-dashboard" {
  source  = "driftlessaf/reconcilers/infra//modules/dashboard/workqueue"
  version = "~> 1.0"

  name            = var.name
  max_retry       = var.max-retry
  concurrent_work = var.concurrent-work
  scope           = var.scope

  labels = {
    team = "platform"
  }

  alerts = {
    "deadletter-alert" = google_monitoring_alert_policy.deadletter.id
  }
}
```

## Features

The dashboard includes:

- **Queue State**: Work in progress, queued items, and items added
- **Processing Metrics**: Processing latency, wait times, and deduplication rates
- **Retry Analytics**: Attempts at completion, maximum attempts, and time to completion
- **Dead Letter Queue**: Monitoring for items that exceeded retry limits (when `max_retry > 0`)
- **Service Logs**: Separate log views for receiver and dispatcher services
- **Alert Integration**: Display configured alerts on the dashboard

## Dashboard Filters

The dashboard automatically configures filters for:
- Receiver service (`${name}-rcv`)
- Dispatcher service (`${name}-dsp`)
- Both Cloud Run built-in metrics and Prometheus custom metrics

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

No providers.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alerts"></a> [alerts](#input\_alerts) | A mapping from alerting policy names to the alert ids to add to the dashboard | `map(string)` | `{}` | no |
| <a name="input_concurrent_work"></a> [concurrent\_work](#input\_concurrent\_work) | The amount of concurrent work to dispatch at a given time | `number` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Additional labels to apply to the dashboard | `map(string)` | `{}` | no |
| <a name="input_max_retry"></a> [max\_retry](#input\_max\_retry) | The maximum number of retry attempts before a task is moved to the dead letter queue | `number` | `20` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the workqueue | `string` | n/a | yes |
| <a name="input_shards"></a> [shards](#input\_shards) | Number of workqueue shards. When > 1, dashboard shows per-shard metrics. | `number` | `1` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_dashboard_json"></a> [dashboard\_json](#output\_dashboard\_json) | The JSON representation of the dashboard |
<!-- END_TF_DOCS -->
