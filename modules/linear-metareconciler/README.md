<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_cloudevents-comments"></a> [cloudevents-comments](#module\_cloudevents-comments) | ../cloudevents-workqueue | n/a |
| <a name="module_cloudevents-issues"></a> [cloudevents-issues](#module\_cloudevents-issues) | ../cloudevents-workqueue | n/a |
| <a name="module_dashboard"></a> [dashboard](#module\_dashboard) | ../dashboard/reconciler | n/a |
| <a name="module_reconciler"></a> [reconciler](#module\_reconciler) | ../regional-go-reconciler | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_broker"></a> [broker](#input\_broker) | A map from region names to the Pub/Sub topic used as a CloudEvents broker | `map(string)` | n/a | yes |
| <a name="input_comment_filters"></a> [comment\_filters](#input\_comment\_filters) | CloudEvents filters for selecting Linear comment events to process.<br/><br/>Comment events carry a `team` extension extracted from the embedded issue<br/>URL by the linear-events trampoline, so they can be filtered by team the<br/>same way as issue events.<br/><br/>Examples:<br/>  # All comment events<br/>  comment\_filters = [<br/>    { "type" = "dev.chainguard.linear.comment" }<br/>  ]<br/><br/>  # Comment events from a specific team<br/>  comment\_filters = [<br/>    { "type" = "dev.chainguard.linear.comment", "team" = "ENG" }<br/>  ] | `list(map(string))` | `[]` | no |
| <a name="input_comment_priority"></a> [comment\_priority](#input\_comment\_priority) | Priority for comment events in the workqueue | `number` | `25` | no |
| <a name="input_comment_skip_authors"></a> [comment\_skip\_authors](#input\_comment\_skip\_authors) | Linear user UUIDs whose comments should NOT trigger reconciliation.<br/><br/>Useful for ignoring comments from automation bots that post to issues<br/>without expecting the reconciler to act (e.g. an issue-sizing bot whose<br/>comments are conversational, not directives). The trampoline emits the<br/>comment author as the `authorid` CloudEvent extension; each entry here<br/>becomes a `NOT attributes.ce-authorid="<uuid>"` clause AND-composed with<br/>`comment_filters`, so matching events are filtered out at the PubSub<br/>subscription layer — the reconciler service is never invoked.<br/><br/>Look up Linear user UUIDs via the GraphQL API or the Linear admin UI;<br/>display names are not used because they can drift if a user renames. | `list(string)` | `[]` | no |
| <a name="input_concurrent-work"></a> [concurrent-work](#input\_concurrent-work) | The amount of concurrent work to dispatch at a given time. | `number` | `1` | no |
| <a name="input_containers"></a> [containers](#input\_containers) | The containers to run in the service. | <pre>map(object({<br/>    source = object({<br/>      base_image  = optional(string, "cgr.dev/chainguard/static:latest-glibc@sha256:60582b2ae6074f641094af0f370d4ab241aab271858a66223dcde7eee9f51638")<br/>      working_dir = string<br/>      importpath  = string<br/>      env         = optional(list(string), [])<br/>    })<br/>    args = optional(list(string), [])<br/>    ports = optional(list(object({<br/>      name           = optional(string, "h2c")<br/>      container_port = number<br/>    })), [])<br/>    resources = optional(<br/>      object(<br/>        {<br/>          limits = optional(object(<br/>            {<br/>              cpu    = string<br/>              memory = string<br/>            }<br/>          ), null)<br/>          cpu_idle          = optional(bool)<br/>          startup_cpu_boost = optional(bool, true)<br/>        }<br/>      ),<br/>      {}<br/>    )<br/>    env = optional(list(object({<br/>      name  = string<br/>      value = optional(string)<br/>      value_source = optional(object({<br/>        secret_key_ref = object({<br/>          secret  = string<br/>          version = string<br/>        })<br/>      }), null)<br/>    })), [])<br/>    regional-env = optional(list(object({<br/>      name  = string<br/>      value = map(string)<br/>    })), [])<br/>    regional-cpu-idle = optional(map(bool), {})<br/>    volume_mounts = optional(list(object({<br/>      name       = string<br/>      mount_path = string<br/>    })), [])<br/>    startup_probe = optional(object({<br/>      initial_delay_seconds = optional(number)<br/>      timeout_seconds       = optional(number, 240)<br/>      period_seconds        = optional(number, 240)<br/>      failure_threshold     = optional(number, 1)<br/>      tcp_socket = optional(object({<br/>        port = optional(number)<br/>      }), null)<br/>      grpc = optional(object({<br/>        port    = optional(number)<br/>        service = optional(string)<br/>      }), null)<br/>    }), null)<br/>    liveness_probe = optional(object({<br/>      initial_delay_seconds = optional(number)<br/>      timeout_seconds       = optional(number)<br/>      period_seconds        = optional(number)<br/>      failure_threshold     = optional(number)<br/>      http_get = optional(object({<br/>        path = optional(string)<br/>        http_headers = optional(list(object({<br/>          name  = string<br/>          value = string<br/>        })), [])<br/>      }), null)<br/>      grpc = optional(object({<br/>        port    = optional(number)<br/>        service = optional(string)<br/>      }), null)<br/>    }), null)<br/>  }))</pre> | n/a | yes |
| <a name="input_dashboard_alerts"></a> [dashboard\_alerts](#input\_dashboard\_alerts) | Alert configurations for the dashboard | `any` | `{}` | no |
| <a name="input_dashboard_labels"></a> [dashboard\_labels](#input\_dashboard\_labels) | Additional labels for the dashboard | `map(string)` | `{}` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Enable deletion protection | `bool` | `true` | no |
| <a name="input_egress"></a> [egress](#input\_egress) | Which type of egress traffic to send through the VPC. | `string` | `"PRIVATE_RANGES_ONLY"` | no |
| <a name="input_error_event_ingress"></a> [error\_event\_ingress](#input\_error\_event\_ingress) | Optional CloudEvents ingress for emitting reconciler error events. Set to null to disable. | <pre>object({<br/>    name = string<br/>  })</pre> | `null` | no |
| <a name="input_issue_filters"></a> [issue\_filters](#input\_issue\_filters) | CloudEvents filters for selecting Linear issue events to process.<br/><br/>Each filter is a map of attribute key-value pairs that must match exactly.<br/>Multiple filters are combined with OR logic.<br/><br/>Examples:<br/>  # All issue events<br/>  issue\_filters = [<br/>    { "type" = "dev.chainguard.linear.issue" }<br/>  ]<br/><br/>  # Issue events from a specific team<br/>  issue\_filters = [<br/>    { "type" = "dev.chainguard.linear.issue", "team" = "ENG" }<br/>  ] | `list(map(string))` | <pre>[<br/>  {<br/>    "type": "dev.chainguard.linear.issue"<br/>  }<br/>]</pre> | no |
| <a name="input_issue_priority"></a> [issue\_priority](#input\_issue\_priority) | Priority for issue events in the workqueue | `number` | `50` | no |
| <a name="input_launch_stage"></a> [launch\_stage](#input\_launch\_stage) | The launch stage of the Cloud Run service (e.g. BETA to leverage features like disk volumes). | `string` | `"GA"` | no |
| <a name="input_max-retry"></a> [max-retry](#input\_max-retry) | The maximum number of times a task will be retried. | `number` | `3` | no |
| <a name="input_name"></a> [name](#input\_name) | Name for the reconciler service | `string` | n/a | yes |
| <a name="input_notification_channels"></a> [notification\_channels](#input\_notification\_channels) | Notification channels for alerts | `list(string)` | `[]` | no |
| <a name="input_observability_role"></a> [observability\_role](#input\_observability\_role) | Fully-qualified id of a single role (e.g. from the observability-role module) to grant the service account in place of the three built-in observability roles (monitoring.metricWriter, cloudtrace.agent, cloudprofiler.agent). Collapsing to one role keeps large projects under the 1,500-member IAM policy limit. | `string` | `null` | no |
| <a name="input_primary-region"></a> [primary-region](#input\_primary-region) | Primary region for the service | `string` | n/a | yes |
| <a name="input_product"></a> [product](#input\_product) | Product label for the service | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID | `string` | n/a | yes |
| <a name="input_regions"></a> [regions](#input\_regions) | A map from region names to a network and subnetwork. | <pre>map(object({<br/>    network = string<br/>    subnet  = string<br/>  }))</pre> | n/a | yes |
| <a name="input_request_timeout_seconds"></a> [request\_timeout\_seconds](#input\_request\_timeout\_seconds) | The request timeout for the service in seconds. | `number` | `300` | no |
| <a name="input_service_account"></a> [service\_account](#input\_service\_account) | Service account email to run the reconciler | `string` | n/a | yes |
| <a name="input_team"></a> [team](#input\_team) | Team label for the service | `string` | n/a | yes |
| <a name="input_trace_event_ingress"></a> [trace\_event\_ingress](#input\_trace\_event\_ingress) | Optional CloudEvents broker for agent-trace and state-transition emission, forwarded to the underlying reconciler. When set, the reconciler is authorized to publish to the named broker and EVENT\_INGRESS\_URI is populated on the reconciler containers. Set to null to disable. | <pre>object({<br/>    name = string<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_receiver"></a> [receiver](#output\_receiver) | The workqueue receiver object for connecting triggers. |
<!-- END_TF_DOCS -->
