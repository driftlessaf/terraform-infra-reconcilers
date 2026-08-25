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

variable "service_account" {
  type        = string
  description = "The service account as which to run the reconciler service."
}

variable "deletion_protection" {
  type        = bool
  description = "Whether to enable delete protection for the service."
  default     = true
}

variable "containers" {
  description = "The containers to run in the service.  Each container will be run in each region."
  type = map(object({
    source = object({
      base_image  = optional(string, "cgr.dev/chainguard/static:latest-glibc@sha256:24dd7ff8788fdfadda39eeeaefefb6d1cec6002a545935a5f7e017484053734f")
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
  description = "The volumes to attach to the service."
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
  description = "The resource clause for the otel sidecar container. Null takes the module default."
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
  description = "Maximum time allowed for a single long-mode job execution (e.g. \"3600s\"). Only used when mode is \"long\"."
  type        = string
  default     = "3600s"
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
  description = "The launch stage of the Cloud Run service (e.g. BETA to leverage features like disk volumes)."
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
