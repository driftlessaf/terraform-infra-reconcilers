# `workqueue`

This module provisions a regionalized workqueue abstraction over Google Cloud
Storage that implements a Kubernetes-like workqueue abstraction for processing
work with concurrency control, in an otherwise stateless fashion (using Google
Cloud Run).

Keys are put into the queue and processed from the queue using a symmetrical
GRPC service definition under `./pkg/workqueue/workqueue.proto`.  This module
takes the name of a service implementing this proto service, and exposes the
name of a service into which work can be enqueued.

```hcl
module "workqueue" {
  source  = "driftlessaf/reconcilers/infra//modules/workqueue"

  project_id = var.project_id
  name       = "${var.name}-workqueue"
  regions    = var.regions

  // The number of keys to process concurrently.
  concurrent-work = 10

  // Maximum number of retry attempts before a task is moved to the dead letter queue
  // Default is 0 (unlimited retries)
  max-retry = 5

  // Optionally disable DLQ alerting while phasing in a queue
  enable_dead_letter_alerting = true

  // It is recommended that folks use a "global" scoped workqueue to get the
  // most accurate deduplication and concurrency control.  The "regional" scope
  // offers regionalized deduplication and concurrency control, but cannot
  // guarantee that receivers and dispatchers in other regions will not process
  // the same key concurrently or redundantly.
  scope = "global"

  // The name of a service that implements the workqueue GRPC service above.
  reconciler-service = {
    name = "foo"
  }

  notification_channels = var.notification_channels
}

// Authorize the bar service to queue keys in our workqueue.
module "bar-queues-keys" {
  for_each = var.regions

  source  = "chainguard-dev/common/infra//modules/authorize-private-service"

  project_id = var.project_id
  region     = each.key
  name       = module.workqueue.receiver.name

  service-account = google_service_account.fanout.email
}

// Stand up the bar service in each of our regions.
module "bar-service" {
  source  = "chainguard-dev/common/infra//modules/regional-go-service"
  ...
      regional-env = [{
        name  = "WORKQUEUE_SERVICE"
        value = { for k, v in module.bar-queues-keys : k => v.uri }
      }]
  ...
}
```

Then the "bar" service initializes a client for the workqueue GRPC service
pointing at `WORKQUEUE_SERVICE` with Cloud Run authentication (see the
`workqueue.NewWorkqueueClient` helper), and queues keys, e.g.

```go
	// Set up the client
	client, err := workqueue.NewWorkqueueClient(ctx, os.Getenv("WORKQUEUE_SERVICE"))
	if err != nil {
		log.Panicf("failed to create client: %v", err)
	}
	defer client.Close()

	// Process a key!
	if _, err := client.Process(ctx, &workqueue.ProcessRequest{
		Key: key,
	}); err != nil {
		log.Panicf("failed to process key: %v", err)
	}
```

## Dashboard

A separate dashboard module is available for monitoring your workqueue. The dashboard provides comprehensive visibility into queue metrics, processing latency, retry patterns, and system health.

```hcl
// Deploy the workqueue dashboard separately
module "workqueue-dashboard" {
  source  = "driftlessaf/reconcilers/infra//modules/dashboard/workqueue"

  // Pass the same configuration used for the workqueue
  name            = var.name
  max_retry       = var.max-retry
  concurrent_work = var.concurrent-work
  scope           = var.scope

  // Optional: Add alert policy IDs
  alerts = {
    "high-retry-alert" = google_monitoring_alert_policy.high_retry.id
  }
}
```

The dashboard includes:
- Queue state visualization (work in progress, queued, added)
- Processing and wait latency metrics
- Retry analytics and completion patterns
- Dead letter queue monitoring (when max-retry is configured)
- Service logs for receiver and dispatcher

See [`modules/dashboard/workqueue`](../dashboard/workqueue/) for more details.

## Maximum Retry and Dead Letter Queue

The workqueue system supports a maximum retry limit for tasks through the `max-retry` variable. When a task fails and gets requeued, the system tracks the number of attempts. Once the maximum retry limit is reached, the task is moved to a dead letter queue instead of being requeued.

- Setting `max-retry = 0` (the default) means unlimited retries
- Setting `max-retry = 5` will move a task to the dead letter queue after 5 failed attempts
- Setting `enable_dead_letter_alerting = false` temporarily suppresses the DLQ alert while you phase in a queue

Tasks in the dead letter queue are stored with their original metadata plus:
- A timestamp in the key name to prevent collisions
- A `failed-time` metadata field indicating when the task was moved to the dead letter queue

Dead-lettered tasks can be inspected using standard GCS tools. They are stored in the workqueue bucket under the `dead-letter/` prefix.

```hcl
module "workqueue" {
  source  = "driftlessaf/reconcilers/infra//modules/workqueue"

  # ... other configuration ...

  // Maximum retry limit (5 attempts before moving to dead letter queue)
  max-retry = 5

  // Optional: disable DLQ alerting during phased rollout
  enable_dead_letter_alerting = false
}
```

### Reenqueuing Dead-Lettered Keys

A Cloud Run Job is automatically created for each workqueue to reenqueue dead-lettered keys. This is useful after deploying a fix for an issue that caused keys to fail repeatedly.

To run the reenqueue job:

```bash
gcloud run jobs execute <workqueue-name>-reenqueue --region <region>
```

The job will:
1. Enumerate all dead-lettered keys in the workqueue
2. Re-queue each key with a fresh attempt counter (preserving the original priority)
3. When the requeued key succeeds, the dead-letter entry is automatically cleaned up

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | n/a |
| <a name="provider_google-beta"></a> [google-beta](#provider\_google-beta) | n/a |
| <a name="provider_random"></a> [random](#provider\_random) | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [google-beta_google_project_service_identity.pubsub](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_project_service_identity) | resource |
| [google_cloud_scheduler_job.cron](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_scheduler_job) | resource |
| [google_monitoring_alert_policy.dead_letter_queue](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_pubsub_subscription.global-this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_subscription) | resource |
| [google_pubsub_topic.global-object-change-notifications](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic) | resource |
| [google_pubsub_topic_iam_binding.global-gcs-publishes-to-topic](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic_iam_binding) | resource |
| [google_service_account.change-trigger](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account.cron-trigger](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account.dispatcher](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account.receiver](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account.reenqueue](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account_iam_binding.allow-pubsub-to-mint-tokens](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_binding) | resource |
| [google_storage_bucket.global-workqueue](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_storage_bucket_iam_binding.global-authorize-access](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_binding) | resource |
| [google_storage_bucket_iam_member.dlq-operators](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [google_storage_bucket_iam_member.reenqueue-bucket-access](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [google_storage_notification.global-object-change-notifications](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_notification) | resource |
| [google_tags_location_tag_binding.global_workqueue_bucket](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/tags_location_tag_binding) | resource |
| [google_tags_tag_binding.global_object_change_topic](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/tags_tag_binding) | resource |
| [google_tags_tag_binding.global_subscription](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/tags_tag_binding) | resource |
| [random_string.bucket_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.change-trigger](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.cron-trigger](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.dispatcher](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.receiver](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.reenqueue](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [google_project.resource_manager_tags](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/project) | data source |
| [google_storage_project_service_account.gcs_account](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/storage_project_service_account) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_batch-size"></a> [batch-size](#input\_batch-size) | Optional cap on how much work to launch per dispatcher pass. Defaults to ceil(concurrent-work / number of regions) when unset. | `number` | `null` | no |
| <a name="input_concurrent-work"></a> [concurrent-work](#input\_concurrent-work) | The amount of concurrent work to dispatch at a given time. | `number` | n/a | yes |
| <a name="input_cpu_idle"></a> [cpu\_idle](#input\_cpu\_idle) | Set to false for a region in order to use instance-based billing. Defaults to true. | `map(map(bool))` | <pre>{<br/>  "dispatcher": {},<br/>  "receiver": {}<br/>}</pre> | no |
| <a name="input_dead_letter_alert_duration"></a> [dead\_letter\_alert\_duration](#input\_dead\_letter\_alert\_duration) | How long the dead-lettered keys count must stay above the threshold before the alert fires (e.g. '0s', '600s'). | `string` | `"0s"` | no |
| <a name="input_dead_letter_alert_threshold"></a> [dead\_letter\_alert\_threshold](#input\_dead\_letter\_alert\_threshold) | Number of dead-lettered keys above which the alert fires. | `number` | `1` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Whether to enable delete protection for the service. | `bool` | `true` | no |
| <a name="input_enable_dead_letter_alerting"></a> [enable\_dead\_letter\_alerting](#input\_enable\_dead\_letter\_alerting) | Whether to enable alerting for dead-lettered keys. | `bool` | `true` | no |
| <a name="input_enable_observability_iam"></a> [enable\_observability\_iam](#input\_enable\_observability\_iam) | Whether the dispatcher service grants its service account the observability roles (monitoring.metricWriter, cloudtrace.agent, cloudprofiler.agent) on the project. Set false only when the caller manages those grants for the dispatcher's service account itself; the standalone workqueue dispatcher runs as a dedicated service account, so the default true is correct there. | `bool` | `true` | no |
| <a name="input_error_event_ingress"></a> [error\_event\_ingress](#input\_error\_event\_ingress) | Optional CloudEvents ingress for emitting reconciler error events. Set to null to disable. | <pre>object({<br/>    name = string<br/>  })</pre> | `null` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to the workqueue resources. | `map(string)` | `{}` | no |
| <a name="input_max-retry"></a> [max-retry](#input\_max-retry) | The maximum number of retry attempts before a task is moved to the dead letter queue. Set this to 0 to have unlimited retries. | `number` | `20` | no |
| <a name="input_multi_regional_location"></a> [multi\_regional\_location](#input\_multi\_regional\_location) | The multi-regional location for the global workqueue bucket (e.g., 'US', 'EU', 'ASIA'). Only used when scope='global'. | `string` | `"US"` | no |
| <a name="input_name"></a> [name](#input\_name) | n/a | `string` | n/a | yes |
| <a name="input_notification_channels"></a> [notification\_channels](#input\_notification\_channels) | List of notification channels to alert. | `list(string)` | n/a | yes |
| <a name="input_observability_role"></a> [observability\_role](#input\_observability\_role) | Fully-qualified id of a single role (e.g. from the observability-role module) to grant the service account in place of the three built-in observability roles (monitoring.metricWriter, cloudtrace.agent, cloudprofiler.agent). Collapsing to one role keeps large projects under the 1,500-member IAM policy limit. | `string` | `null` | no |
| <a name="input_owner-concurrent-work"></a> [owner-concurrent-work](#input\_owner-concurrent-work) | Optional cap on concurrent work owned by each dispatcher region. Must be a positive integer when set. The global concurrent-work cap also applies. | `number` | `null` | no |
| <a name="input_primary-region"></a> [primary-region](#input\_primary-region) | The primary region for single-homed resources like the reenqueue job. Defaults to the first region in the regions map. | `string` | `null` | no |
| <a name="input_product"></a> [product](#input\_product) | Product label to apply to the service. | `string` | `"unknown"` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | n/a | `string` | n/a | yes |
| <a name="input_receiver_ingress"></a> [receiver\_ingress](#input\_receiver\_ingress) | The ingress traffic setting for the workqueue receiver service. INGRESS\_TRAFFIC\_ALL allows callers outside the VPC (e.g. Cloud Run services without VPC egress) to enqueue work. | `string` | `"INGRESS_TRAFFIC_INTERNAL_ONLY"` | no |
| <a name="input_reconciler-service"></a> [reconciler-service](#input\_reconciler-service) | The name of the reconciler service that the workqueue will dispatch work to. | <pre>object({<br/>    name = string<br/>  })</pre> | n/a | yes |
| <a name="input_regions"></a> [regions](#input\_regions) | A map from region names to a network and subnetwork.  A service will be created in each region configured to egress the specified traffic via the specified subnetwork. | <pre>map(object({<br/>    network = string<br/>    subnet  = string<br/>  }))</pre> | n/a | yes |
| <a name="input_resource_manager_tags"></a> [resource\_manager\_tags](#input\_resource\_manager\_tags) | Resource Manager tags to bind to this module's taggable resources, as tagKeys/<id> => tagValues/<id>. | `map(string)` | `{}` | no |
| <a name="input_scope"></a> [scope](#input\_scope) | The scope of the workqueue. Must be 'global' for a single multi-regional workqueue. | `string` | `"global"` | no |
| <a name="input_team"></a> [team](#input\_team) | Team label to apply to resources (replaces deprecated 'squad'). | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bucket"></a> [bucket](#output\_bucket) | The name of the GCS bucket backing the workqueue. |
| <a name="output_dispatcher"></a> [dispatcher](#output\_dispatcher) | n/a |
| <a name="output_receiver"></a> [receiver](#output\_receiver) | n/a |
<!-- END_TF_DOCS -->
