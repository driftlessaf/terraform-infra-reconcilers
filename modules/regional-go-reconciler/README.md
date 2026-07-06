# Regional Go Reconciler Module

This module combines a workqueue with a regional Go service to create a complete reconciler setup. It stands up both the workqueue infrastructure (receiver and dispatcher) and a reconciler service that processes events from the workqueue.

## Usage

```hcl
module "my-reconciler" {
  source  = "driftlessaf/reconcilers/infra//modules/regional-go-reconciler"
  version = "~> 1.0"

  project_id = var.project_id
  name       = "my-reconciler"
  regions    = var.regions

  service_account = google_service_account.reconciler.email

  containers = {
    "reconciler" = {
      source = {
        working_dir = path.module
        importpath  = "./cmd/reconciler"
      }
      ports = [{
        container_port = 8080
      }]
    }
  }

  notification_channels = [var.notification_channel]
}
```

## Features

- **Integrated Workqueue**: Automatically sets up a workqueue with receiver and dispatcher services
- **Regional Deployment**: Deploys reconciler services in multiple regions with workqueue infrastructure
- **Flexible Configuration**: Supports both regional and global workqueue scopes
- **Built from Source**: Uses ko to build Go binaries directly from source
- **Monitoring**: Includes dashboards and metrics for both workqueue and service

## Architecture

The module creates:
1. A workqueue (using the `workqueue` module) with:
   - Receiver service (`${name}-rcv`) that accepts events
   - Dispatcher service (`${name}-dsp`) that processes the queue
   - GCS buckets for queue storage
   - Pub/Sub topics and subscriptions
2. A reconciler service (using the `regional-go-service` module) that:
   - Receives events from the dispatcher
   - Processes them according to your business logic
   - Can be configured with custom containers and environment variables

## Workqueue Service Protocol

Your reconciler should implement the workqueue proto service:

```go
type Reconciler struct {
    workqueue.UnimplementedWorkqueueServiceServer
    // your fields
}

func (r *Reconciler) Process(ctx context.Context, req *workqueue.ProcessRequest) (*workqueue.ProcessResponse, error) {
    // Process the event
    err := r.reconcile(ctx, req.Key)
    if err != nil {
        // Requeue with delay
        if delay, ok := workqueue.GetRequeueDelay(err); ok {
            return &workqueue.ProcessResponse{
                RequeueAfterSeconds: int64(delay.Seconds()),
            }, nil
        }
        // Non-retriable error
        if workqueue.IsNonRetriableError(err) {
            return nil, status.Error(codes.InvalidArgument, err.Error())
        }
        // Retriable error
        return nil, err
    }
    return &workqueue.ProcessResponse{}, nil
}
```

## Monitoring

A dedicated dashboard module is available for monitoring:

```hcl
module "my-reconciler-dashboard" {
  source  = "driftlessaf/reconcilers/infra//modules/dashboard/workqueue"
  version = "~> 1.0"

  name       = "my-reconciler"
  project_id = var.project_id

  max_retry       = module.my-reconciler.max_retry
  concurrent_work = module.my-reconciler.concurrent_work
  scope           = module.my-reconciler.scope
}
```

## Variables

See [variables.tf](./variables.tf) for all available configuration options.

## Outputs

| Name | Description |
|------|-------------|
| `workqueue-receiver` | The name of the workqueue receiver service |
| `reconciler-uri` | The URI of the reconciler service |
| `workqueue-topic` | The workqueue topic name |
| `workqueue-dashboards` | Dashboard outputs for monitoring |

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_google"></a> [google](#provider\_google) | n/a |
| <a name="provider_google-beta"></a> [google-beta](#provider\_google-beta) | n/a |
| <a name="provider_random"></a> [random](#provider\_random) | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_change-trigger-calls-dispatcher"></a> [change-trigger-calls-dispatcher](#module\_change-trigger-calls-dispatcher) | ../../../../public/terraform-infra-common/modules/authorize-private-service | n/a |
| <a name="module_cron-trigger-calls-dispatcher"></a> [cron-trigger-calls-dispatcher](#module\_cron-trigger-calls-dispatcher) | ../../../../public/terraform-infra-common/modules/authorize-private-service | n/a |
| <a name="module_dispatcher-calls-error-broker"></a> [dispatcher-calls-error-broker](#module\_dispatcher-calls-error-broker) | ../../../../public/terraform-infra-common/modules/authorize-private-service | n/a |
| <a name="module_dispatcher-calls-target"></a> [dispatcher-calls-target](#module\_dispatcher-calls-target) | ../../../../public/terraform-infra-common/modules/authorize-private-service | n/a |
| <a name="module_dispatcher-service"></a> [dispatcher-service](#module\_dispatcher-service) | ../../../../public/terraform-infra-common/modules/regional-go-service | n/a |
| <a name="module_receiver-service"></a> [receiver-service](#module\_receiver-service) | ../../../../public/terraform-infra-common/modules/regional-go-service | n/a |
| <a name="module_reconciler"></a> [reconciler](#module\_reconciler) | ../../../../public/terraform-infra-common/modules/regional-go-service | n/a |
| <a name="module_reconciler-job"></a> [reconciler-job](#module\_reconciler-job) | ../../../../public/terraform-infra-common/modules/regional-go-cron | n/a |
| <a name="module_reconciler-publishes-traces"></a> [reconciler-publishes-traces](#module\_reconciler-publishes-traces) | ../../../../public/terraform-infra-common/modules/authorize-private-service | n/a |
| <a name="module_reenqueue"></a> [reenqueue](#module\_reenqueue) | ../../../../public/terraform-infra-common/modules/cron | n/a |

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
| [random_string.bucket_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.change-trigger](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.cron-trigger](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.dispatcher](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.receiver](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.reenqueue](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [google_storage_project_service_account.gcs_account](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/storage_project_service_account) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_batch-size"></a> [batch-size](#input\_batch-size) | Optional cap on how much work to launch per dispatcher pass. | `number` | `null` | no |
| <a name="input_concurrent-work"></a> [concurrent-work](#input\_concurrent-work) | The amount of concurrent work to dispatch at a given time. | `number` | `20` | no |
| <a name="input_containers"></a> [containers](#input\_containers) | The containers to run in the service.  Each container will be run in each region. | <pre>map(object({<br/>    source = object({<br/>      base_image  = optional(string, "cgr.dev/chainguard/static:latest-glibc@sha256:77d8b8925dc27970ec2f48243f44c7a260d52c49cd778288e4ee97566e0cb75b")<br/>      working_dir = string<br/>      importpath  = string<br/>      env         = optional(list(string), [])<br/>    })<br/>    command = optional(list(string), [])<br/>    args    = optional(list(string), [])<br/>    ports = optional(list(object({<br/>      name           = optional(string, "h2c")<br/>      container_port = number<br/>    })), [])<br/>    resources = optional(<br/>      object(<br/>        {<br/>          limits = optional(object(<br/>            {<br/>              cpu    = string<br/>              memory = string<br/>            }<br/>          ), null)<br/>          cpu_idle          = optional(bool)<br/>          startup_cpu_boost = optional(bool, true)<br/>        }<br/>      ),<br/>      {}<br/>    )<br/>    env = optional(list(object({<br/>      name  = string<br/>      value = optional(string)<br/>      value_source = optional(object({<br/>        secret_key_ref = object({<br/>          secret  = string<br/>          version = string<br/>        })<br/>      }), null)<br/>    })), [])<br/>    regional-env = optional(list(object({<br/>      name  = string<br/>      value = map(string)<br/>    })), [])<br/>    regional-cpu-idle = optional(map(bool), {})<br/>    volume_mounts = optional(list(object({<br/>      name       = string<br/>      mount_path = string<br/>    })), [])<br/>    startup_probe = optional(object({<br/>      initial_delay_seconds = optional(number)<br/>      timeout_seconds       = optional(number, 240)<br/>      period_seconds        = optional(number, 240)<br/>      failure_threshold     = optional(number, 1)<br/>      tcp_socket = optional(object({<br/>        port = optional(number)<br/>      }), null)<br/>      grpc = optional(object({<br/>        port    = optional(number)<br/>        service = optional(string)<br/>      }), null)<br/>    }), null)<br/>    liveness_probe = optional(object({<br/>      initial_delay_seconds = optional(number)<br/>      timeout_seconds       = optional(number)<br/>      period_seconds        = optional(number)<br/>      failure_threshold     = optional(number)<br/>      http_get = optional(object({<br/>        path = optional(string)<br/>        http_headers = optional(list(object({<br/>          name  = string<br/>          value = string<br/>        })), [])<br/>      }), null)<br/>      grpc = optional(object({<br/>        port    = optional(number)<br/>        service = optional(string)<br/>      }), null)<br/>    }), null)<br/>  }))</pre> | `{}` | no |
| <a name="input_dead_letter_alert_duration"></a> [dead\_letter\_alert\_duration](#input\_dead\_letter\_alert\_duration) | How long the dead-lettered keys count must stay above the threshold before the alert fires (e.g. '0s', '600s'). | `string` | `"0s"` | no |
| <a name="input_dead_letter_alert_threshold"></a> [dead\_letter\_alert\_threshold](#input\_dead\_letter\_alert\_threshold) | Number of dead-lettered keys above which the alert fires. | `number` | `1` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Whether to enable delete protection for the service. | `bool` | `true` | no |
| <a name="input_dlq_operators"></a> [dlq\_operators](#input\_dlq\_operators) | IAM members granted roles/storage.objectAdmin on the workqueue bucket for dead-letter queue operations (inspect, drain, purge). Format: "user:email" or "serviceAccount:email". | `list(string)` | `[]` | no |
| <a name="input_egress"></a> [egress](#input\_egress) | Which type of egress traffic to send through the VPC.<br/><br/>- ALL\_TRAFFIC sends all traffic through regional VPC network. This should be used if service is not expected to egress to the Internet.<br/>- PRIVATE\_RANGES\_ONLY sends only traffic to private IP addresses through regional VPC network | `string` | `"ALL_TRAFFIC"` | no |
| <a name="input_enable_dead_letter_alerting"></a> [enable\_dead\_letter\_alerting](#input\_enable\_dead\_letter\_alerting) | Whether to enable alerting for dead-lettered keys. | `bool` | `true` | no |
| <a name="input_enable_profiler"></a> [enable\_profiler](#input\_enable\_profiler) | Enable continuous profiling for the service.  This has a small performance impact, which shouldn't matter for production services. | `bool` | `false` | no |
| <a name="input_error_event_ingress"></a> [error\_event\_ingress](#input\_error\_event\_ingress) | Optional CloudEvents ingress for emitting reconciler error events. Set to null to disable. | <pre>object({<br/>    name = string<br/>  })</pre> | `null` | no |
| <a name="input_execution_environment"></a> [execution\_environment](#input\_execution\_environment) | The execution environment for the service (options: EXECUTION\_ENVIRONMENT\_GEN1, EXECUTION\_ENVIRONMENT\_GEN2). | `string` | `"EXECUTION_ENVIRONMENT_GEN2"` | no |
| <a name="input_job_timeout"></a> [job\_timeout](#input\_job\_timeout) | Maximum time allowed for a single long-mode job execution (e.g. "3600s"). Only used when mode is "long". | `string` | `"3600s"` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Additional labels to add to all resources. | `map(string)` | `{}` | no |
| <a name="input_launch_stage"></a> [launch\_stage](#input\_launch\_stage) | The launch stage of the Cloud Run service (e.g. BETA to leverage features like disk volumes). | `string` | `"GA"` | no |
| <a name="input_max-retry"></a> [max-retry](#input\_max-retry) | The maximum number of times a task will be retried before being moved to the dead-letter queue. Set to 0 for unlimited retries. Defaults to null so the inner workqueue module's default applies. | `number` | `null` | no |
| <a name="input_mode"></a> [mode](#input\_mode) | Reconciler mode. "short" (default) runs a long-lived Cloud Run service for the dispatcher. "long" runs a Cloud Run Job per cron tick, suitable for reconciliations that exceed Cloud Run's request timeout. | `string` | `"short"` | no |
| <a name="input_multi_regional_location"></a> [multi\_regional\_location](#input\_multi\_regional\_location) | The multi-regional location for the global workqueue bucket. Options: US, EU, ASIA. | `string` | `"US"` | no |
| <a name="input_name"></a> [name](#input\_name) | n/a | `string` | n/a | yes |
| <a name="input_notification_channels"></a> [notification\_channels](#input\_notification\_channels) | The channels to send notifications to. List of channel IDs | `list(string)` | `[]` | no |
| <a name="input_otel_resources"></a> [otel\_resources](#input\_otel\_resources) | Resources to add to the OpenTelemetry resource. | `map(string)` | `{}` | no |
| <a name="input_primary-region"></a> [primary-region](#input\_primary-region) | The primary region for single-homed resources like the reenqueue job. Defaults to the first region in the regions map. | `string` | `null` | no |
| <a name="input_product"></a> [product](#input\_product) | The product that this service belongs to. | `string` | `""` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | n/a | `string` | n/a | yes |
| <a name="input_receiver_ingress"></a> [receiver\_ingress](#input\_receiver\_ingress) | Ingress traffic setting for the workqueue receiver Cloud Run service. Defaults to INGRESS\_TRAFFIC\_INTERNAL\_ONLY. Set INGRESS\_TRAFFIC\_ALL to allow IAM-gated callers outside this project's VPC (e.g. a cross-project Cloud Run / GKE caller without VPC peering) to enqueue; the receiver still requires roles/run.invoker. | `string` | `"INGRESS_TRAFFIC_INTERNAL_ONLY"` | no |
| <a name="input_regional-volumes"></a> [regional-volumes](#input\_regional-volumes) | The volumes to make available to the containers in the service for mounting. | <pre>list(object({<br/>    name = string<br/>    gcs = optional(map(object({<br/>      bucket        = string<br/>      read_only     = optional(bool, true)<br/>      mount_options = optional(list(string), [])<br/>    })), {})<br/>    nfs = optional(map(object({<br/>      server    = string<br/>      path      = string<br/>      read_only = optional(bool, true)<br/>    })), {})<br/>  }))</pre> | `[]` | no |
| <a name="input_regions"></a> [regions](#input\_regions) | A map from region names to a network and subnetwork.  A service will be created in each region configured to egress the specified traffic via the specified subnetwork. | <pre>map(object({<br/>    network = string<br/>    subnet  = string<br/>  }))</pre> | n/a | yes |
| <a name="input_request_timeout_seconds"></a> [request\_timeout\_seconds](#input\_request\_timeout\_seconds) | The request timeout for the service in seconds. | `number` | `300` | no |
| <a name="input_scaling"></a> [scaling](#input\_scaling) | The scaling configuration for the service. | <pre>object({<br/>    min_instances                    = optional(number, 0)<br/>    max_instances                    = optional(number, 100)<br/>    max_instance_request_concurrency = optional(number, 1000)<br/>  })</pre> | `{}` | no |
| <a name="input_service_account"></a> [service\_account](#input\_service\_account) | The service account as which to run the reconciler service. | `string` | n/a | yes |
| <a name="input_slo"></a> [slo](#input\_slo) | Configuration for setting up SLO for the cloud run service | <pre>object({<br/>    enable          = optional(bool, false)<br/>    enable_alerting = optional(bool, false)<br/>    success = optional(object(<br/>      {<br/>        multi_region_goal = optional(number, 0.999)<br/>        per_region_goal   = optional(number, 0.999)<br/>      }<br/>    ), null)<br/>    monitor_gclb = optional(bool, false)<br/>  })</pre> | `{}` | no |
| <a name="input_team"></a> [team](#input\_team) | Team label to apply to resources (replaces deprecated 'squad'). | `string` | n/a | yes |
| <a name="input_trace_event_ingress"></a> [trace\_event\_ingress](#input\_trace\_event\_ingress) | Optional CloudEvents broker for agent-trace emission. When set, the reconciler service account is authorized to publish to the named broker and EVENT\_INGRESS\_URI is appended to every reconciler container's regional env; agenttrace then emits dev.chainguard.driftlessaf.agent.trace.v1 events per agent invocation. Set to null to disable. | <pre>object({<br/>    name = string<br/>  })</pre> | `null` | no |
| <a name="input_volumes"></a> [volumes](#input\_volumes) | The volumes to attach to the service. | <pre>list(object({<br/>    name = string<br/>    empty_dir = optional(object({<br/>      medium     = optional(string, "MEMORY")<br/>      size_limit = optional(string, "1Gi")<br/>    }), null)<br/>    csi = optional(object({<br/>      driver = string<br/>      volume_attributes = optional(object({<br/>        bucketName = string<br/>      }), null)<br/>    }), null)<br/>  }))</pre> | `[]` | no |
| <a name="input_workqueue_cpu_idle"></a> [workqueue\_cpu\_idle](#input\_workqueue\_cpu\_idle) | Set to false for a region in order to use instance-based billing for workqueue services (dispatcher and receiver). Defaults to true. To control reconciler cpu\_idle, use the 'regional-cpu-idle' field in the 'containers' variable. | `map(map(bool))` | <pre>{<br/>  "dispatcher": {},<br/>  "receiver": {}<br/>}</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bucket"></a> [bucket](#output\_bucket) | The name of the GCS bucket backing the workqueue. |
| <a name="output_receiver"></a> [receiver](#output\_receiver) | The workqueue receiver object for connecting triggers. |
| <a name="output_reconciler-uris"></a> [reconciler-uris](#output\_reconciler-uris) | The URIs of the reconciler service by region (short mode only). |
<!-- END_TF_DOCS -->
