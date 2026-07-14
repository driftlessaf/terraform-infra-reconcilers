<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_cloudevents-issues"></a> [cloudevents-issues](#module\_cloudevents-issues) | ../cloudevents-workqueue | n/a |
| <a name="module_cloudevents-prs"></a> [cloudevents-prs](#module\_cloudevents-prs) | ../cloudevents-workqueue | n/a |
| <a name="module_dashboard"></a> [dashboard](#module\_dashboard) | ../dashboard/reconciler | n/a |
| <a name="module_reconciler"></a> [reconciler](#module\_reconciler) | ../regional-go-reconciler | n/a |

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
| <a name="input_dead_letter_alert_duration"></a> [dead\_letter\_alert\_duration](#input\_dead\_letter\_alert\_duration) | How long the dead-lettered keys count must stay above the threshold before the alert fires (e.g. '0s', '600s'). | `string` | `"0s"` | no |
| <a name="input_dead_letter_alert_threshold"></a> [dead\_letter\_alert\_threshold](#input\_dead\_letter\_alert\_threshold) | Number of dead-lettered keys above which the alert fires. | `number` | `1` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Enable deletion protection | `bool` | `true` | no |
| <a name="input_dlq_operators"></a> [dlq\_operators](#input\_dlq\_operators) | IAM members granted roles/storage.objectAdmin on the workqueue bucket for dead-letter queue operations (inspect, drain, purge). Format: "user:email" or "serviceAccount:email". | `list(string)` | `[]` | no |
| <a name="input_egress"></a> [egress](#input\_egress) | Which type of egress traffic to send through the VPC. | `string` | `"PRIVATE_RANGES_ONLY"` | no |
| <a name="input_error_event_ingress"></a> [error\_event\_ingress](#input\_error\_event\_ingress) | Optional CloudEvents ingress for emitting reconciler error events. Set to null to disable. | <pre>object({<br/>    name = string<br/>  })</pre> | `null` | no |
| <a name="input_filters"></a> [filters](#input\_filters) | CloudEvents filters for selecting events to process (applied to both issue and PR events) | `list(map(string))` | `[]` | no |
| <a name="input_issue_priority"></a> [issue\_priority](#input\_issue\_priority) | Priority for issue events in the workqueue | `number` | `50` | no |
| <a name="input_launch_stage"></a> [launch\_stage](#input\_launch\_stage) | The launch stage of the Cloud Run service (e.g. BETA to leverage features like disk volumes). | `string` | `"GA"` | no |
| <a name="input_max-retry"></a> [max-retry](#input\_max-retry) | The maximum number of times a task will be retried. | `number` | `3` | no |
| <a name="input_microvm"></a> [microvm](#input\_microvm) | Add the microvm dashboard sections (control-plane + agent-pod metrics). The agent-pod section is scoped to the reconciler's octo-sts identity, which by convention equals the GKE namespace its microvm agents run in. Requires octo\_sts\_identity to be set. | `bool` | `false` | no |
| <a name="input_name"></a> [name](#input\_name) | Name for the reconciler service | `string` | n/a | yes |
| <a name="input_notification_channels"></a> [notification\_channels](#input\_notification\_channels) | Notification channels for alerts | `list(string)` | `[]` | no |
| <a name="input_observability_role"></a> [observability\_role](#input\_observability\_role) | Fully-qualified id of a single role (e.g. from the observability-role module) to grant the service account in place of the three built-in observability roles (monitoring.metricWriter, cloudtrace.agent, cloudprofiler.agent). Collapsing to one role keeps large projects under the 1,500-member IAM policy limit. | `string` | `null` | no |
| <a name="input_octo_sts_identity"></a> [octo\_sts\_identity](#input\_octo\_sts\_identity) | The reconciler's octo-sts identity (the same value passed to the binary as<br/>OCTO\_IDENTITY). Used only to scope PR events when own\_prs\_only is set, since<br/>changemanager names this reconciler's branches "<octo\_sts\_identity>/...".<br/>Filter-only here: unlike github-metapathreconciler this module wires no auth to<br/>it (the binary handles GitHub auth itself). | `string` | `""` | no |
| <a name="input_own_prs_only"></a> [own\_prs\_only](#input\_own\_prs\_only) | Scope the PR-event subscription to PRs this reconciler authored — those on<br/>branches named "<octo\_sts\_identity>/...". Never affects the issues subscription<br/>(issue events carry no headbranch).<br/><br/>Defaults true, since most reconcilers only act on their own PRs. Set false for<br/>reconcilers that act on PRs they did NOT author, since scoping to own branches<br/>would hide those PRs. | `bool` | `true` | no |
| <a name="input_pr_priority"></a> [pr\_priority](#input\_pr\_priority) | Priority for PR events in the workqueue | `number` | `200` | no |
| <a name="input_primary-region"></a> [primary-region](#input\_primary-region) | Primary region for the service | `string` | n/a | yes |
| <a name="input_product"></a> [product](#input\_product) | Product label for the service | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID | `string` | n/a | yes |
| <a name="input_regions"></a> [regions](#input\_regions) | A map from region names to a network and subnetwork. | <pre>map(object({<br/>    network = string<br/>    subnet  = string<br/>  }))</pre> | n/a | yes |
| <a name="input_request_timeout_seconds"></a> [request\_timeout\_seconds](#input\_request\_timeout\_seconds) | The request timeout for the service in seconds. | `number` | `300` | no |
| <a name="input_service_account"></a> [service\_account](#input\_service\_account) | Service account email to run the reconciler | `string` | n/a | yes |
| <a name="input_team"></a> [team](#input\_team) | Team label for the service | `string` | n/a | yes |
| <a name="input_trace_event_ingress"></a> [trace\_event\_ingress](#input\_trace\_event\_ingress) | Optional CloudEvents broker for agent-trace emission, forwarded to the underlying reconciler. When set, the reconciler is authorized to publish to the named broker and EVENT\_INGRESS\_URI is populated on the reconciler containers. Set to null to disable. | <pre>object({<br/>    name = string<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_receiver"></a> [receiver](#output\_receiver) | The workqueue receiver object for connecting triggers. |
<!-- END_TF_DOCS -->
