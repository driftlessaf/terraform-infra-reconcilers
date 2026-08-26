/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

# All variables from regional-go-reconciler

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

variable "mode" {
  description = "Reconciler mode. \"short\" (default) runs a long-lived Cloud Run service for the dispatcher. \"long\" runs a Cloud Run Job per cron tick, suitable for reconciliations that exceed Cloud Run's request timeout."
  type        = string
  default     = "short"
  validation {
    condition     = contains(["short", "long"], var.mode)
    error_message = "mode must be \"short\" or \"long\""
  }
}

variable "job_timeout" {
  description = "Maximum time allowed for a single long-mode job execution (e.g. \"3600s\"). Only used when mode is \"long\"."
  type        = string
  default     = "3600s"
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

variable "concurrent-work" {
  description = "The amount of concurrent work to dispatch at a given time."
  type        = number
  default     = 20
}

variable "regional-concurrent-work" {
  description = "Optional cap on concurrent work in each dispatcher region. Must be a positive integer when set. The global concurrent-work cap also applies."
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
    args = optional(list(string), [])
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
  description = "The scaling configuration for the service."
  type = object({
    min_instances                    = optional(number, 0)
    max_instances                    = optional(number, 100)
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
  default     = true
}

variable "otel_resources" {
  description = "The resource clause for the otel sidecar container. Null inherits the reconciler default."
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

# New variables for github-path-reconciler

variable "repos" {
  description = "Repositories to watch, each with their own path patterns and resync period."
  type = list(object({
    owner         = string
    repo          = string
    path_patterns = list(string)
    # exclude_patterns: optional list of regex patterns (no capture group required).
    # Anchors ^ and $ are added automatically. A pattern like ".*/testdata/.*" matches
    # any path containing a testdata/ segment, but NOT a root-level testdata/ path
    # (e.g. "testdata/fixture.go") since ^ requires a prefix before the first /.
    # To also exclude root-level testdata, use "(testdata/.*|.*/testdata/.*)".
    exclude_patterns = optional(list(string), [])
    # resync_period_hours: how often this repo's matched paths are reconciled
    # by the resync cron. Must be a positive multiple of resync_floor_hours
    # and at most 744 (31 days).
    resync_period_hours = number
  }))
  validation {
    condition     = alltrue([for r in var.repos : r.resync_period_hours >= 1 && r.resync_period_hours <= 744 && r.resync_period_hours % var.resync_floor_hours == 0])
    error_message = "Each repo's resync_period_hours must be between 1 and 744 and a positive multiple of resync_floor_hours."
  }
}

variable "resync_floor_hours" {
  description = "Cron firing cadence and shard size, in hours. This is the minimum granularity for any per-repo resync_period_hours; all per-repo periods must be a positive multiple of this value."
  type        = number
  default     = 1
  validation {
    condition     = var.resync_floor_hours >= 1 && var.resync_floor_hours <= 24 && 24 % var.resync_floor_hours == 0
    error_message = "resync_floor_hours must be between 1 and 24 hours and divide 24 evenly."
  }
}

variable "octo_sts_identity" {
  description = "Octo STS identity for GitHub authentication. Also used as the config file name."
  type        = string
}

variable "github_app_id" {
  description = "GitHub App ID. When non-zero, the push listener and resync cron authenticate using the app instead of Octo STS."
  type        = number
  default     = 0
  validation {
    condition     = length(var.repos) > 0 || var.github_app_id != 0
    error_message = "At least one of repos (non-empty) or github_app_id must be specified."
  }
}

variable "github_app_key" {
  description = "Key URI for the GitHub App private key (e.g. gcpkms://...). Required when github_app_id is non-zero."
  type        = string
  default     = ""
  validation {
    condition     = var.github_app_id == 0 || var.github_app_key != ""
    error_message = "github_app_key must be set when github_app_id is non-zero."
  }
}

variable "primary-region" {
  description = "The primary region to run the cron job in"
  type        = string
}

variable "paused" {
  description = "Whether to pause both the cron service and push listener"
  type        = bool
  default     = false
}

variable "broker" {
  description = "A map from each of the input region names to the name of the Broker topic in that region."
  type        = map(string)
}

variable "error_event_ingress" {
  description = "Optional CloudEvents ingress for emitting reconciler error events. Set to null to disable."
  type = object({
    name = string
  })
  default = null
}

variable "trace_event_ingress" {
  description = "Optional CloudEvents broker for agent-trace emission, forwarded to the underlying reconciler. When set, the reconciler is authorized to publish to the named broker and EVENT_INGRESS_URI is populated on the reconciler containers. Set to null to disable."
  type = object({
    name = string
  })
  default = null
}

variable "launch_stage" {
  description = "The launch stage of the Cloud Run service (e.g. BETA to leverage features like disk volumes)."
  type        = string
  default     = "GA"
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
