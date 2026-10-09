/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

variable "project_id" {
  type = string
}

variable "name" {
  type = string
}

variable "regions" {
  description = "A map from region names to a network and subnetwork.  A service will be created in each region configured to egress the specified traffic via the specified subnetwork."
  type = map(object({
    network = string
    subnet  = string
  }))
}

variable "primary-region" {
  description = "The primary region for single-homed resources like the reenqueue job. Defaults to the first region in the regions map."
  type        = string
  default     = null
}

// Workqueue-specific variables

variable "mode" {
  description = "Reconciler mode. \"short\" (default) runs a long-lived Cloud Run service for the dispatcher. \"long\" runs a Cloud Run Job per cron tick, suitable for reconciliations that exceed Cloud Run's request timeout."
  type        = string
  default     = "short"
  validation {
    condition     = contains(["short", "long"], var.mode)
    error_message = "mode must be \"short\" or \"long\""
  }
}

variable "receiver_ingress" {
  description = "Ingress traffic setting for the workqueue receiver Cloud Run service. Defaults to INGRESS_TRAFFIC_INTERNAL_ONLY. Set INGRESS_TRAFFIC_ALL to allow IAM-gated callers outside this project's VPC (e.g. a cross-project Cloud Run / GKE caller without VPC peering) to enqueue; the receiver still requires roles/run.invoker."
  type        = string
  default     = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  validation {
    condition     = contains(["INGRESS_TRAFFIC_ALL", "INGRESS_TRAFFIC_INTERNAL_ONLY", "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"], var.receiver_ingress)
    error_message = "receiver_ingress must be one of INGRESS_TRAFFIC_ALL, INGRESS_TRAFFIC_INTERNAL_ONLY, INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER."
  }
}

variable "shards" {
  description = "Number of workqueue shards. When 1, uses the standard workqueue. When >1, uses hyperqueue."
  type        = number
  default     = 1

  validation {
    condition     = var.shards >= 1 && var.shards <= 5
    error_message = "shards must be between 1 and 5"
  }

  validation {
    condition     = var.shards == 1 || var.mode == "short"
    error_message = "sharded workqueues (shards > 1) are incompatible with long mode"
  }
}

variable "max-retry" {
  description = "The maximum number of times a task will be retried before being moved to the dead-letter queue. Set to 0 for unlimited retries. Defaults to null so the inner workqueue module's default applies."
  type        = number
  default     = null
}

variable "enable_dead_letter_alerting" {
  description = "Whether to enable alerting for dead-lettered keys."
  type        = bool
  default     = true
}

variable "dead_letter_alert_threshold" {
  description = "Number of dead-lettered keys above which the alert fires."
  type        = number
  default     = 1
}

variable "dead_letter_alert_duration" {
  description = "How long the dead-lettered keys count must stay above the threshold before the alert fires (e.g. '0s', '600s')."
  type        = string
  default     = "0s"
}

variable "concurrent-work" {
  description = "The amount of concurrent work to dispatch at a given time."
  type        = number
  default     = 20
}

variable "candidate-window-factor" {
  description = "How far each dispatch pass shuffles its candidates, as a multiple of the keys that pass can launch (window = factor x launch slots). Any whole number is valid, there are no special steps. 0 disables the shuffle: every dispatcher takes the head of the queue, so dispatchers sharing a queue race for the same keys and lose most contested claims. Raising it spreads dispatchers over more keys, lowering lost claims, at the cost of how long a key can sit unpicked (up to the factor in passes when only one dispatcher is running). Measured with three dispatchers, lost-claim share of the slowest: 16 -> 11.2%, 24 -> 8.0%, 32 -> 6.5%, 48 -> 4.2%, 64 -> 3.4%. 48 is the smallest that keeps the slowest dispatcher under 5% and is the library default (dispatcher.DefaultCandidateWindowFactor); the module defaults to 0 so spreading is opt-in per environment. Go lower only if pick latency matters more than contention, higher only if loss is still high with more dispatchers. Above about 96 the window reaches the enumeration limit and larger values change nothing, so the input is capped at 128."
  type        = number
  default     = 0

  validation {
    condition     = var.candidate-window-factor >= 0 && var.candidate-window-factor <= 128 && var.candidate-window-factor == floor(var.candidate-window-factor)
    error_message = "candidate-window-factor must be a whole number from 0 to 128. 0 disables spreading; 48 is the measured recommendation; values above about 96 have no additional effect because the window is clipped to the enumerated list."
  }
}

variable "dispatch_period" {
  description = "Short mode only. Minimum spacing between dispatch passes each dispatcher instance admits, as a Go duration. Passes may overlap, and a pass with free slots lists the whole queued prefix, so a longer period bounds how many full listings a deep queue starts. Triggers inside the period are acknowledged and dropped."
  type        = string
  default     = "1s"

  validation {
    condition     = can(regex("^[1-9][0-9]{0,5}(ms|s|m)$", var.dispatch_period))
    error_message = "dispatch_period must be a positive Go duration of at most six digits with one unit (for example, 1s or 60s)."
  }

  validation {
    condition     = var.shards == 1 || var.dispatch_period == "1s"
    error_message = "dispatch_period is not forwarded to sharded workqueues; leave it at 1s when shards > 1."
  }
}

variable "dispatcher_max_instances" {
  description = "Optional cap on dispatcher service instances in each region, applied to each revision and to the service across revisions. Short mode only. Each instance admits its own dispatch passes, and every admitted pass with free slots lists the whole queued prefix, so a deep queue costs one full listing per admitted pass on every instance. Cloud Run may briefly exceed the cap. Unset leaves the regional-go-service defaults on a dispatcher that was never capped; to remove a cap, set 100, because unsetting it keeps the deployed service-level cap."
  type        = number
  default     = null

  validation {
    condition     = var.dispatcher_max_instances == null ? true : var.dispatcher_max_instances >= 1 && floor(var.dispatcher_max_instances) == var.dispatcher_max_instances
    error_message = "dispatcher_max_instances must be a positive integer when set."
  }

  validation {
    condition     = var.shards == 1 || var.dispatcher_max_instances == null
    error_message = "dispatcher_max_instances is not forwarded to sharded workqueues; leave it unset when shards > 1."
  }
}

variable "regional-concurrent-work" {
  description = "Optional cap on concurrent work in each dispatcher region. Defaults to ceil(concurrent-work / number of regions) when unset. Must be a positive integer when set. The global concurrent-work cap also applies."
  type        = number
  default     = null

  validation {
    condition     = var.regional-concurrent-work == null ? true : var.regional-concurrent-work > 0 && floor(var.regional-concurrent-work) == var.regional-concurrent-work
    error_message = "regional-concurrent-work must be a positive integer when set."
  }
}

variable "batch-size" {
  description = "Optional cap on how much work to launch per dispatcher pass."
  type        = number
  default     = null
}

variable "multi_regional_location" {
  description = "The multi-regional location for the global workqueue bucket. Options: US, EU, ASIA."
  type        = string
  default     = "US"
  validation {
    condition     = contains(["US", "EU", "ASIA"], var.multi_regional_location)
    error_message = "multi_regional_location must be one of: US, EU, ASIA."
  }
}

// Service-specific variables

variable "egress" {
  type        = string
  description = <<EOD
Which type of egress traffic to send through the VPC.

- ALL_TRAFFIC sends all traffic through regional VPC network. This should be used if service is not expected to egress to the Internet.
- PRIVATE_RANGES_ONLY sends only traffic to private IP addresses through regional VPC network
EOD
  default     = "ALL_TRAFFIC"
}

variable "regional-connector" {
  type        = map(string)
  description = <<EOD
Forwarded to regional-go-service (reconciler, dispatcher, receiver) and
regional-go-cron (long-mode reconciler-job). Optional per-region Serverless
VPC Access connector, keyed by region name, as a fully qualified id
projects/<project>/locations/<region>/connectors/<name>. A region present here
egresses through the connector instead of direct VPC egress — either because
Cloud NAT does not translate direct VPC egress from a Shared-VPC service
project, or to amortize network-interface provisioning across instances
instead of allocating one per instance/revision.

Not forwarded when shards > 1 — the sharded workqueue path (workqueue/hyperqueue)
does not currently support a connector.
EOD
  default     = {}
}

variable "service_account" {
  type        = string
  description = "The service account as which to run the reconciler service."
}

variable "deletion_protection" {
  type        = bool
  description = "Whether to enable delete protection for the service."
  default     = true
}

variable "raw_containers" {
  description = "Additional prebuilt containers for the reconciler service in short mode only; keys must not collide with containers. Uses regional-go-service's raw_containers schema. Images are neither built nor signed by this module; pin trusted images by digest. Sidecars must leave ports empty. The service renderer supports args, resources, env, regional-env, regional-cpu-idle and volume_mounts for sidecars, but does not apply command, startup_probe or liveness_probe, or configure startup dependencies."
  type = map(object({
    image   = string
    command = optional(list(string), [])
    args    = optional(list(string), [])
    ports = optional(list(object({
      name           = optional(string, "http1")
      container_port = number
    })), [])
    resources = optional(
      object(
        {
          limits = optional(object(
            {
              cpu    = string
              memory = string
            }
          ), null)
          cpu_idle          = optional(bool)
          startup_cpu_boost = optional(bool, true)
        }
      ),
      {}
    )
    env = optional(list(object({
      name  = string
      value = optional(string)
      value_source = optional(object({
        secret_key_ref = object({
          secret  = string
          version = string
        })
      }), null)
    })), [])
    regional-env = optional(list(object({
      name  = string
      value = map(string)
    })), [])
    regional-cpu-idle = optional(map(bool), {})
    volume_mounts = optional(list(object({
      name       = string
      mount_path = string
    })), [])
    startup_probe = optional(object({
      initial_delay_seconds = optional(number)
      // GCP Terraform provider defaults differ from Cloud Run defaults.
      // See https://cloud.google.com/run/docs/configuring/healthchecks#tcp-startup-probe
      period_seconds    = optional(number, 240)
      timeout_seconds   = optional(number, 240)
      failure_threshold = optional(number, 1)
      http_get = optional(object({
        path = string
        port = optional(number)
      }), null)
      tcp_socket = optional(object({
        port = optional(number)
      }), null)
      grpc = optional(object({
        service = optional(string)
        port    = optional(number)
      }), null)
    }))
    liveness_probe = optional(object({
      initial_delay_seconds = optional(number)
      // GCP Terraform provider defaults differ from Cloud Run defaults.
      // See https://cloud.google.com/run/docs/configuring/healthchecks#tcp-startup-probe
      period_seconds    = optional(number, 240)
      timeout_seconds   = optional(number, 240)
      failure_threshold = optional(number, 1)
      http_get = optional(object({
        path = string
        port = optional(number)
      }), null)
      tcp_socket = optional(object({
        port = optional(number)
      }), null)
      grpc = optional(object({
        service = optional(string)
        port    = optional(number)
      }), null)
    }))
  }))
  default  = {}
  nullable = false

  validation {
    condition     = var.mode == "short" || length(var.raw_containers) == 0
    error_message = "raw_containers is supported only in short mode (Cloud Run services); long mode (Cloud Run Jobs) requires raw_containers to be empty."
  }
}

variable "containers" {
  description = "The containers to run in the service.  Each container will be run in each region."
  type = map(object({
    source = object({
      base_image  = optional(string, "cgr.dev/chainguard/static:latest-glibc@sha256:bf639cba19ba56329e6907ac26a7afcdde57a80b6aa66d5100da6883196e6b82")
      working_dir = string
      importpath  = string
      env         = optional(list(string), [])
    })
    command = optional(list(string), [])
    args    = optional(list(string), [])
    ports = optional(list(object({
      name           = optional(string, "h2c")
      container_port = number
    })), [])
    resources = optional(
      object(
        {
          limits = optional(object(
            {
              cpu    = string
              memory = string
            }
          ), null)
          cpu_idle          = optional(bool)
          startup_cpu_boost = optional(bool, true)
        }
      ),
      {}
    )
    env = optional(list(object({
      name  = string
      value = optional(string)
      value_source = optional(object({
        secret_key_ref = object({
          secret  = string
          version = string
        })
      }), null)
    })), [])
    regional-env = optional(list(object({
      name  = string
      value = map(string)
    })), [])
    regional-cpu-idle = optional(map(bool), {})
    volume_mounts = optional(list(object({
      name       = string
      mount_path = string
    })), [])
    startup_probe = optional(object({
      initial_delay_seconds = optional(number)
      timeout_seconds       = optional(number, 240)
      period_seconds        = optional(number, 240)
      failure_threshold     = optional(number, 1)
      tcp_socket = optional(object({
        port = optional(number)
      }), null)
      grpc = optional(object({
        port    = optional(number)
        service = optional(string)
      }), null)
    }), null)
    liveness_probe = optional(object({
      initial_delay_seconds = optional(number)
      timeout_seconds       = optional(number)
      period_seconds        = optional(number)
      failure_threshold     = optional(number)
      http_get = optional(object({
        path = optional(string)
        http_headers = optional(list(object({
          name  = string
          value = string
        })), [])
      }), null)
      grpc = optional(object({
        port    = optional(number)
        service = optional(string)
      }), null)
    }), null)
  }))
  default = {}
}

// Common variables

variable "labels" {
  description = "Additional labels to add to all resources."
  type        = map(string)
  default     = {}
}

variable "team" {
  description = "Team label to apply to resources (replaces deprecated 'squad')."
  type        = string
}

variable "product" {
  description = "The product that this service belongs to."
  type        = string
  default     = ""
}

variable "scaling" {
  description = "The scaling configuration for the service. max_instances bounds each revision individually; service_max_instances additionally bounds all revisions receiving traffic combined, which Cloud Run requires when per-instance ephemeral disk reservations must fit the regional quota across rollouts."
  type = object({
    min_instances                    = optional(number, 0)
    max_instances                    = optional(number, 100)
    service_max_instances            = optional(number)
    max_instance_request_concurrency = optional(number, 1000)
  })
  default = {}
}

variable "volumes" {
  description = "The volumes to attach to the reconciler in both modes: the short-mode service receives every entry, and the long-mode job receives the empty_dir entries only (csi volumes are service-only)."
  type = list(object({
    name = string
    empty_dir = optional(object({
      medium     = optional(string, "MEMORY")
      size_limit = optional(string, "1Gi")
    }), null)
    csi = optional(object({
      driver = string
      volume_attributes = optional(object({
        bucketName = string
      }), null)
    }), null)
  }))
  default = []
}

variable "regional-volumes" {
  description = "The volumes to make available to the containers in the service for mounting."
  type = list(object({
    name = string
    gcs = optional(map(object({
      bucket        = string
      read_only     = optional(bool, true)
      mount_options = optional(list(string), [])
    })), {})
    nfs = optional(map(object({
      server    = string
      path      = string
      read_only = optional(bool, true)
    })), {})
  }))
  default = []
}

variable "enable_profiler" {
  description = "Enable continuous profiling for the service.  This has a small performance impact, which shouldn't matter for production services."
  type        = bool
  default     = false
}

variable "enable_observability_iam" {
  description = "Whether the components that run as the shared service account grant it the observability roles (monitoring.metricWriter, cloudtrace.agent, cloudprofiler.agent) on the project: the short-mode reconciler and dispatcher services and the long-mode reconciler job. Set false when the caller manages these grants itself for the shared service account, to avoid overlapping non-authoritative IAM members that revoke each other on destroy. The receiver and re-enqueue components use dedicated service accounts and are unaffected."
  type        = bool
  default     = true
}

variable "otel_resources" {
  description = "The resource clause for the otel sidecar container. Short mode applies it to the reconciler service; long mode applies its limits to the reconciler job. Null takes the default of the module that runs the sidecar."
  type = object({
    limits = optional(object(
      {
        cpu    = string
        memory = string
      }
    ), null)
    cpu_idle          = optional(bool)
    startup_cpu_boost = optional(bool)
  })
  default = null
}

variable "request_timeout_seconds" {
  description = "The request timeout for the service in seconds."
  type        = number
  default     = 300
}

variable "job_timeout" {
  description = "Maximum time allowed for a single long-mode job execution (e.g. \"3600s\"). Every reconcile in the execution must also return 2 minutes before it, so one that would run out the clock counts as a failed attempt and dead-letters after max_retry instead of retrying forever. Only used when mode is \"long\"."
  type        = string
  default     = "3600s"
}

variable "scheduled_wait_warning_threshold" {
  description = "Duration after which claiming an eligible GCS workqueue key emits a structured warning (for example, \"1h\"). Set to \"0s\" to disable."
  type        = string
  default     = "0s"

  validation {
    condition = (
      can(regex("^(0s|[1-9][0-9]*(ns|us|µs|ms|s|m|h))$", var.scheduled_wait_warning_threshold)) &&
      can(timeadd("2000-01-01T00:00:00Z", var.scheduled_wait_warning_threshold))
    )
    error_message = "scheduled_wait_warning_threshold must be 0s or a positive Go duration with one unit (for example, 30m or 1h)."
  }
}

variable "claim_window" {
  description = "Long mode only: how long after it starts a job execution keeps claiming keys into its free slots (every claim_poll, while it still has work in flight) instead of claiming once at startup. \"0s\" keeps the single pass at startup. Leave room for a key claimed at the end of the window to finish 2 minutes before job_timeout; a window that reaches that deadline fails the job at startup."
  type        = string
  default     = "0s"

  validation {
    condition = (
      can(regex("^(0s|[1-9][0-9]*(ns|us|µs|ms|s|m|h))$", var.claim_window)) &&
      can(timeadd("2000-01-01T00:00:00Z", var.claim_window))
    )
    error_message = "claim_window must be 0s or a positive Go duration with one unit (for example, 600s or 10m)."
  }
}

variable "schedule" {
  description = "Long mode only: the unix-cron schedule on which Cloud Scheduler starts a job execution in each region, either \"* * * * *\" or \"*/N * * * *\" with N from 1 to 15. Every execution bills at least one minute of the full job shape (Cloud Run Jobs' minimum), even when the queue is empty, so a queue that is usually idle can trade pickup latency for cost with e.g. \"*/5 * * * *\". A key enqueued while no execution is running waits for the next tick."
  type        = string
  default     = "* * * * *"

  validation {
    // Capped at every 15 minutes: idle executions are what publish the
    // dead-letter gauge, and the dead-letter alert auto-closes an hour after
    // its last sample. At the cap, even if the next two executions are missed,
    // the one after them starts 45 minutes after the last sample, leaving 15
    // minutes for startup before a standing backlog could falsely resolve and
    // re-page.
    condition     = can(regex("^(\\*|\\*/([1-9]|1[0-5])) \\* \\* \\* \\*$", var.schedule))
    error_message = "schedule must be \"* * * * *\" or \"*/N * * * *\" with N from 1 to 15 (for example, \"*/5 * * * *\")."
  }
}

variable "claim_poll" {
  description = "Long mode only: how often, jittered by up to half either way, a job execution inside its claim_window looks for keys to claim into its free slots."
  type        = string
  default     = "10s"

  validation {
    condition = (
      can(regex("^[1-9][0-9]*(ms|s|m)$", var.claim_poll)) &&
      can(timeadd("2000-01-01T00:00:00Z", var.claim_poll))
    )
    error_message = "claim_poll must be a positive Go duration with one unit (for example, 10s)."
  }
}

variable "execution_environment" {
  description = "The execution environment for the service (options: EXECUTION_ENVIRONMENT_GEN1, EXECUTION_ENVIRONMENT_GEN2)."
  type        = string
  default     = "EXECUTION_ENVIRONMENT_GEN2"
}

variable "notification_channels" {
  description = "The channels to send notifications to. List of channel IDs"
  type        = list(string)
  default     = []
}

variable "workqueue_cpu_idle" {
  description = "Set to false for a region in order to use instance-based billing for workqueue services (dispatcher and receiver). Defaults to true. To control reconciler cpu_idle, use the 'regional-cpu-idle' field in the 'containers' variable."
  type        = map(map(bool))
  default = {
    "dispatcher" = {}
    "receiver"   = {}
  }
}

variable "error_event_ingress" {
  description = "Optional CloudEvents ingress for emitting reconciler error events. Set to null to disable."
  type = object({
    name = string
  })
  default = null
}

variable "trace_event_ingress" {
  description = "Optional CloudEvents broker for agent-trace emission. When set, the reconciler service account is authorized to publish to the named broker and EVENT_INGRESS_URI is appended to every reconciler container's regional env; agenttrace then emits dev.chainguard.driftlessaf.agent.trace.v1 events per agent invocation. Set to null to disable."
  type = object({
    name = string
  })
  default = null
}

variable "slo" {
  description = "Configuration for setting up SLO for the cloud run service"
  type = object({
    enable          = optional(bool, false)
    enable_alerting = optional(bool, false)
    success = optional(object(
      {
        multi_region_goal = optional(number, 0.999)
        per_region_goal   = optional(number, 0.999)
      }
    ), null)
    monitor_gclb = optional(bool, false)
  })
  default = {}
}

variable "launch_stage" {
  description = "The launch stage of the Cloud Run service and, in long mode, of the Cloud Run job (e.g. BETA to leverage features like disk volumes)."
  type        = string
  default     = "GA"
}

variable "dlq_operators" {
  description = "IAM members granted roles/storage.objectAdmin on the workqueue bucket for dead-letter queue operations (inspect, drain, purge). Format: \"user:email\" or \"serviceAccount:email\"."
  type        = list(string)
  default     = []
}

variable "reenqueue_invokers" {
  description = "IAM members granted roles/run.invoker on the (manually-triggered) reenqueue Cloud Run job, allowing them to execute it to requeue dead-lettered workqueue items. Format: \"user:email\", \"group:email\", or \"serviceAccount:email\"."
  type        = list(string)
  default     = []
}

variable "reenqueue_schedule" {
  description = "Cron schedule on which the reenqueue job periodically drains the dead-letter queue, so transient dead-letters (e.g. an upstream 5xx that outlasts the retry budget) self-heal without an operator. When null (the default) the job stays paused for manual invocation only. Genuinely-permanent failures dead-letter again on the next run and keep the DLQ alert firing."
  type        = string
  default     = null
}
variable "observability_role" {
  type        = string
  default     = null
  description = "Fully-qualified id of a single role (e.g. from the observability-role module) to grant the service account in place of the three built-in observability roles (monitoring.metricWriter, cloudtrace.agent, cloudprofiler.agent). Collapsing to one role keeps large projects under the 1,500-member IAM policy limit."

  validation {
    condition     = var.observability_role == null || can(regex("^(projects|organizations)/[^/]+/roles/[^/]+$", var.observability_role))
    error_message = "observability_role must be a fully-qualified role id: projects/{project}/roles/{role_id} or organizations/{org}/roles/{role_id}."
  }
}

variable "resource_manager_tags" {
  description = "Resource Manager tags to bind to this module's taggable resources, as tagKeys/<id> => tagValues/<id>."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for key, value in var.resource_manager_tags :
      can(regex("^tagKeys/[0-9]+$", key)) && can(regex("^tagValues/[0-9]+$", value))
    ])
    error_message = "resource_manager_tags keys must be tagKeys/<numeric-id> and values must be tagValues/<numeric-id>."
  }
}

variable "queue_readers" {
  description = <<-EOT
    IAM members granted read-only access (roles/storage.objectViewer) to the
    workqueue bucket. For producers that read the queue's depth to decide whether
    to enqueue more — see gcs.QueuedDepth. The two other bindings onto this bucket
    both grant delete, which is more than a count needs.
  EOT
  type        = list(string)
  default     = []
}
