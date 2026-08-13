# Reconciler Dashboard Module

This module creates a comprehensive dashboard for monitoring a reconciler that combines a workqueue with a reconciler service. It displays metrics from both the workqueue infrastructure (receiver and dispatcher) and the reconciler service itself.

## Usage

```hcl
module "my-reconciler-dashboard" {
  source  = "driftlessaf/reconcilers/infra//modules/dashboard/reconciler"
  version = "~> 1.0"

  project_id = var.project_id
  name       = "my-reconciler"

  # Optional: Override service names if different from defaults
  # service_name   = "custom-reconciler-name"  # defaults to ${name}-rec
  # workqueue_name = "custom-workqueue-name"    # defaults to ${name}-wq

  # Workqueue configuration
  max_retry       = 100
  concurrent_work = 20

  # Optional sections
  sections = {
    github = false
  }

  notification_channels = [var.notification_channel]
}
```

## Features

The dashboard includes:

### Workqueue Metrics
- **Workqueue State**: Work in progress, queued, added, deduplication rates, completion attempts
- **Processing Metrics**: Process latency, wait latency, time to completion
- **Dead Letter Queue**: Failed tasks monitoring

### Reconciler Service Metrics
- **Error Reporting**: Error tracking and reporting for the reconciler (collapsed by default)
- **Service Logs**: Reconciler service logs
- **gRPC Metrics**: RPC rates, latencies, error rates
- **GitHub API Metrics**: API usage and rate limiting (optional)
- **Resources**: CPU, memory, and other resource utilization

### microvm Metrics (separate dashboard)

When the `microvm` section is enabled, the control-plane and agent-pod metrics are published to their own `Reconciler microvm: <name>` dashboard rather than this one. They add 14 widgets, which would push a reconciler that also enables `github` and `agents` past Cloud Monitoring's 50-widget-per-dashboard limit.

## Variables

| Name | Description | Default |
|------|-------------|---------|
| `project_id` | The GCP project ID | Required |
| `name` | Base name for the reconciler | Required |
| `service_name` | Reconciler service name | `${name}-rec` |
| `workqueue_name` | Workqueue name | `${name}-wq` |
| `max_retry` | Maximum retry attempts for tasks | `100` |
| `concurrent_work` | Concurrent work items | `20` |
| `sections` | Optional dashboard sections | See variables.tf |
| `service_sections` | Service-specific sections appended to the layout | `[]` |
| `notification_channels` | Alert notification channels | `[]` |

## Outputs

| Name | Description |
|------|-------------|
| `json` | The dashboard JSON configuration |

## Integration with regional-go-reconciler

This dashboard module is designed to work seamlessly with the `regional-go-reconciler` module:

```hcl
module "my-reconciler" {
  source  = "driftlessaf/reconcilers/infra//modules/regional-go-reconciler"
  version = "~> 1.0"
  # ... configuration ...
}

module "my-reconciler-dashboard" {
  source  = "driftlessaf/reconcilers/infra//modules/dashboard/reconciler"
  version = "~> 1.0"

  project_id      = var.project_id
  name            = "my-reconciler"  # Same base name as the reconciler
  max_retry       = module.my-reconciler.max-retry
  concurrent_work = module.my-reconciler.concurrent-work
}
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
| <a name="input_alerts"></a> [alerts](#input\_alerts) | Map of alert names to alert configurations | <pre>map(object({<br/>    displayName         = string<br/>    documentation       = string<br/>    userLabels          = map(string)<br/>    project             = string<br/>    notificationChannel = string<br/>  }))</pre> | `{}` | no |
| <a name="input_concurrent_work"></a> [concurrent\_work](#input\_concurrent\_work) | The amount of concurrent work the workqueue dispatches | `number` | `20` | no |
| <a name="input_service_sections"></a> [service\_sections](#input\_service\_sections) | Service-specific dashboard sections (outputs of dashboard/sections/* modules) appended to the layout before the resources section | `list(any)` | `[]` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Additional labels to add to the dashboard | `map(string)` | `{}` | no |
| <a name="input_max_retry"></a> [max\_retry](#input\_max\_retry) | The maximum number of retry attempts for workqueue tasks | `number` | `20` | no |
| <a name="input_mode"></a> [mode](#input\_mode) | Reconciler mode: "short" (Cloud Run Service) or "long" (Cloud Run Job per cron tick) | `string` | `"short"` | no |
| <a name="input_name"></a> [name](#input\_name) | The name of the reconciler (base name without suffixes) | `string` | n/a | yes |
| <a name="input_notification_channels"></a> [notification\_channels](#input\_notification\_channels) | List of notification channels for alerts | `list(string)` | `[]` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID | `string` | n/a | yes |
| <a name="input_sections"></a> [sections](#input\_sections) | Configure visibility of optional dashboard sections | <pre>object({<br/>    github = optional(bool, false)<br/>    agents = optional(bool, false)<br/>    // microvm, unlike the others, is a namespace string rather than a bool:<br/>    // set it to the GKE namespace this reconciler's microvm agent pods run in<br/>    // to add the control-plane (scoped by service_name) and agent-pod (scoped<br/>    // to that namespace) sections. Null omits them.<br/>    microvm = optional(string, null)<br/>  })</pre> | `{}` | no |
| <a name="input_service_name"></a> [service\_name](#input\_service\_name) | The name of the reconciler service (defaults to name-rec) | `string` | `""` | no |
| <a name="input_shards"></a> [shards](#input\_shards) | Number of workqueue shards. When > 1, dashboard shows per-shard metrics. | `number` | `1` | no |
| <a name="input_workqueue_name"></a> [workqueue\_name](#input\_workqueue\_name) | The name of the workqueue (defaults to name-wq) | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_json"></a> [json](#output\_json) | n/a |
<!-- END_TF_DOCS -->
