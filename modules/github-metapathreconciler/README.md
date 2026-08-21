<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_cloudevents-prs"></a> [cloudevents-prs](#module\_cloudevents-prs) | ../cloudevents-workqueue | n/a |
| <a name="module_dashboard"></a> [dashboard](#module\_dashboard) | ../dashboard/reconciler | n/a |
| <a name="module_reconciler"></a> [reconciler](#module\_reconciler) | ../github-path-reconciler | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_broker"></a> [broker](#input\_broker) | A map from region names to the Pub/Sub topic used as a CloudEvents broker | `map(string)` | n/a | yes |
| <a name="input_concurrent-work"></a> [concurrent-work](#input\_concurrent-work) | The amount of concurrent work to dispatch at a given time. | `number` | `1` | no |
| <a name="input_containers"></a> [containers](#input\_containers) | The containers to run in the service. | <pre>map(object({<br/>    source = object({<br/>      base_image  = optional(string, "cgr.dev/chainguard/static:latest-glibc@sha256:60582b2ae6074f641094af0f370d4ab241aab271858a66223dcde7eee9f51638")<br/>      working_dir = string<br/>      importpath  = string<br/>      env         = optional(list(string), [])<br/>    })<br/>    args = optional(list(string), [])<br/>    ports = optional(list(object({<br/>      name           = optional(string, "h2c")<br/>      container_port = number<br/>    })), [])<br/>    resources = optional(<br/>      object(<br/>        {<br/>          limits = optional(object(<br/>            {<br/>              cpu    = string<br/>              memory = string<br/>            }<br/>          ), null)<br/>          cpu_idle          = optional(bool)<br/>          startup_cpu_boost = optional(bool, true)<br/>        }<br/>      ),<br/>      {}<br/>    )<br/>    env = optional(list(object({<br/>      name  = string<br/>      value = optional(string)<br/>      value_source = optional(object({<br/>        secret_key_ref = object({<br/>          secret  = string<br/>          version = string<br/>        })<br/>      }), null)<br/>    })), [])<br/>    regional-env = optional(list(object({<br/>      name  = string<br/>      value = map(string)<br/>    })), [])<br/>    regional-cpu-idle = optional(map(bool), {})<br/>    volume_mounts = optional(list(object({<br/>      name       = string<br/>      mount_path = string<br/>    })), [])<br/>    startup_probe = optional(object({<br/>      initial_delay_seconds = optional(number)<br/>      timeout_seconds       = optional(number, 240)<br/>      period_seconds        = optional(number, 240)<br/>      failure_threshold     = optional(number, 1)<br/>      tcp_socket = optional(object({<br/>        port = optional(number)<br/>      }), null)<br/>      grpc = optional(object({<br/>        port    = optional(number)<br/>        service = optional(string)<br/>      }), null)<br/>    }), null)<br/>    liveness_probe = optional(object({<br/>      initial_delay_seconds = optional(number)<br/>      timeout_seconds       = optional(number)<br/>      period_seconds        = optional(number)<br/>      failure_threshold     = optional(number)<br/>      http_get = optional(object({<br/>        path = optional(string)<br/>        http_headers = optional(list(object({<br/>          name  = string<br/>          value = string<br/>        })), [])<br/>      }), null)<br/>      grpc = optional(object({<br/>        port    = optional(number)<br/>        service = optional(string)<br/>      }), null)<br/>    }), null)<br/>  }))</pre> | n/a | yes |
| <a name="input_dashboard_alerts"></a> [dashboard\_alerts](#input\_dashboard\_alerts) | Alert configurations for the dashboard | `any` | `{}` | no |
| <a name="input_dashboard_labels"></a> [dashboard\_labels](#input\_dashboard\_labels) | Additional labels for the dashboard | `map(string)` | `{}` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Enable deletion protection | `bool` | `true` | no |
| <a name="input_egress"></a> [egress](#input\_egress) | Which type of egress traffic to send through the VPC. | `string` | `"PRIVATE_RANGES_ONLY"` | no |
| <a name="input_enable_dead_letter_alerting"></a> [enable\_dead\_letter\_alerting](#input\_enable\_dead\_letter\_alerting) | Whether to enable alerting for dead-lettered keys. | `bool` | `true` | no |
| <a name="input_error_event_ingress"></a> [error\_event\_ingress](#input\_error\_event\_ingress) | Optional CloudEvents ingress for emitting reconciler error events. Set to null to disable. | <pre>object({<br/>    name = string<br/>  })</pre> | `null` | no |
| <a name="input_github_app_id"></a> [github\_app\_id](#input\_github\_app\_id) | GitHub App ID. When non-zero, the push listener and resync cron authenticate using the app instead of Octo STS. | `number` | `0` | no |
| <a name="input_github_app_key"></a> [github\_app\_key](#input\_github\_app\_key) | Key URI for the GitHub App private key (e.g. gcpkms://...). Required when github\_app\_id is non-zero. | `string` | `""` | no |
| <a name="input_job_timeout"></a> [job\_timeout](#input\_job\_timeout) | Maximum time allowed for a single long-mode job execution (e.g. "3600s"). Only used when mode is "long". | `string` | `"3600s"` | no |
| <a name="input_launch_stage"></a> [launch\_stage](#input\_launch\_stage) | The launch stage of the Cloud Run service (e.g. BETA to leverage features like disk volumes). | `string` | `"GA"` | no |
| <a name="input_max-retry"></a> [max-retry](#input\_max-retry) | The maximum number of times a task will be retried. | `number` | `3` | no |
| <a name="input_microvm"></a> [microvm](#input\_microvm) | Add the microvm dashboard sections (control-plane + agent-pod metrics). The agent-pod section is scoped to the reconciler's octo-sts identity, which by convention equals the GKE namespace its microvm agents run in. Requires octo\_sts\_identity to be set. | `bool` | `false` | no |
| <a name="input_mode"></a> [mode](#input\_mode) | Reconciler mode. "short" (default) runs a long-lived Cloud Run service for the dispatcher. "long" runs a Cloud Run Job per cron tick, suitable for reconciliations that exceed Cloud Run's request timeout. | `string` | `"short"` | no |
| <a name="input_name"></a> [name](#input\_name) | Name for the reconciler service | `string` | n/a | yes |
| <a name="input_notification_channels"></a> [notification\_channels](#input\_notification\_channels) | Notification channels for alerts | `list(string)` | `[]` | no |
| <a name="input_observability_role"></a> [observability\_role](#input\_observability\_role) | Fully-qualified id of a single role (e.g. from the observability-role module) to grant the service account in place of the three built-in observability roles (monitoring.metricWriter, cloudtrace.agent, cloudprofiler.agent). Collapsing to one role keeps large projects under the 1,500-member IAM policy limit. | `string` | `null` | no |
| <a name="input_octo_sts_identity"></a> [octo\_sts\_identity](#input\_octo\_sts\_identity) | Octo STS identity for GitHub authentication. Also used as the config file name. | `string` | n/a | yes |
| <a name="input_own_prs_only"></a> [own\_prs\_only](#input\_own\_prs\_only) | Scope the PR-event subscription to PRs this reconciler authored — those on<br/>branches named "<octo\_sts\_identity>/..." (changemanager's convention). The push<br/>listener has its own subscription, which this does not affect.<br/><br/>Defaults true, since most reconcilers only act on their own PRs. Set false for<br/>reconcilers that act on PRs they did NOT author — e.g. those running in a review<br/>or config mode — since scoping to own branches would hide the very PRs they<br/>exist to review. | `bool` | `true` | no |
| <a name="input_paused"></a> [paused](#input\_paused) | Whether to pause the reconciler and event subscriptions | `bool` | `false` | no |
| <a name="input_pr_priority"></a> [pr\_priority](#input\_pr\_priority) | Priority for PR events in the workqueue | `number` | `200` | no |
| <a name="input_primary-region"></a> [primary-region](#input\_primary-region) | Primary region for the service | `string` | n/a | yes |
| <a name="input_product"></a> [product](#input\_product) | Product label for the service | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID | `string` | n/a | yes |
| <a name="input_regions"></a> [regions](#input\_regions) | A map from region names to a network and subnetwork. | <pre>map(object({<br/>    network = string<br/>    subnet  = string<br/>  }))</pre> | n/a | yes |
| <a name="input_repos"></a> [repos](#input\_repos) | Repositories to watch, each with their own path patterns and resync period. | <pre>list(object({<br/>    owner               = string<br/>    repo                = string<br/>    path_patterns       = list(string)<br/>    exclude_patterns    = optional(list(string), [])<br/>    resync_period_hours = number<br/>  }))</pre> | n/a | yes |
| <a name="input_request_timeout_seconds"></a> [request\_timeout\_seconds](#input\_request\_timeout\_seconds) | The request timeout for the service in seconds. | `number` | `300` | no |
| <a name="input_resource_manager_tags"></a> [resource\_manager\_tags](#input\_resource\_manager\_tags) | Resource Manager tags to bind to this module's taggable resources, as tagKeys/<id> => tagValues/<id>. | `map(string)` | `{}` | no |
| <a name="input_resync_floor_hours"></a> [resync\_floor\_hours](#input\_resync\_floor\_hours) | Cron firing cadence and shard size, in hours. This is the minimum granularity for any per-repo resync\_period\_hours. | `number` | `1` | no |
| <a name="input_scaling"></a> [scaling](#input\_scaling) | Scaling configuration for the reconciler service. Set max\_instance\_request\_concurrency to 1 to run one reconcile per instance (scale out), which is appropriate for heavy per-key work (clones, builds, agents) that cannot share an instance. | <pre>object({<br/>    min_instances                    = optional(number, 0)<br/>    max_instances                    = optional(number, 100)<br/>    max_instance_request_concurrency = optional(number, 1000)<br/>  })</pre> | `{}` | no |
| <a name="input_service_account"></a> [service\_account](#input\_service\_account) | Service account email to run the reconciler | `string` | n/a | yes |
| <a name="input_team"></a> [team](#input\_team) | Team label for the service | `string` | n/a | yes |
| <a name="input_trace_event_ingress"></a> [trace\_event\_ingress](#input\_trace\_event\_ingress) | Optional CloudEvents broker for agent-trace emission, forwarded to the underlying reconciler. When set, the reconciler is authorized to publish to the named broker and EVENT\_INGRESS\_URI is populated on the reconciler containers. Set to null to disable. | <pre>object({<br/>    name = string<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_receiver"></a> [receiver](#output\_receiver) | The workqueue receiver object for connecting triggers. |
<!-- END_TF_DOCS -->
