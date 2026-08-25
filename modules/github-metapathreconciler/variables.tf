/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

variable "project_id" {
  type        = string
  description = "The GCP project ID"
}

variable "name" {
  type        = string
  description = "Name for the reconciler service"
}

variable "regions" {
  description = "A map from region names to a network and subnetwork."
  type = map(object({
    network = string
    subnet  = string
  }))
}

variable "primary-region" {
  type        = string
  description = "Primary region for the service"
}

variable "service_account" {
  type        = string
  description = "Service account email to run the reconciler"
}

variable "broker" {
  description = "A map from region names to the Pub/Sub topic used as a CloudEvents broker"
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

variable "containers" {
  description = "The containers to run in the service."
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
}

variable "concurrent-work" {
  description = "The amount of concurrent work to dispatch at a given time."
  type        = number
  default     = 1
}

variable "scaling" {
  description = "Scaling configuration for the reconciler service. Set max_instance_request_concurrency to 1 to run one reconcile per instance (scale out), which is appropriate for heavy per-key work (clones, builds, agents) that cannot share an instance."
  type = object({
    min_instances                    = optional(number, 0)
    max_instances                    = optional(number, 100)
    max_instance_request_concurrency = optional(number, 1000)
  })
  default = {}
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
  description = "The maximum number of times a task will be retried."
  type        = number
  default     = 3
}

variable "egress" {
  type        = string
  description = "Which type of egress traffic to send through the VPC."
  default     = "PRIVATE_RANGES_ONLY"
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

variable "notification_channels" {
  type        = list(string)
  description = "Notification channels for alerts"
  default     = []
}

variable "deletion_protection" {
  type        = bool
  description = "Enable deletion protection"
  default     = true
}

variable "team" {
  type        = string
  description = "Team label for the service"
}

variable "product" {
  type        = string
  description = "Product label for the service"
}

# Path reconciler variables

variable "repos" {
  description = "Repositories to watch, each with their own path patterns and resync period."
  type = list(object({
    owner               = string
    repo                = string
    path_patterns       = list(string)
    exclude_patterns    = optional(list(string), [])
    resync_period_hours = number
  }))
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

variable "resync_floor_hours" {
  description = "Cron firing cadence and shard size, in hours. This is the minimum granularity for any per-repo resync_period_hours."
  type        = number
  default     = 1
}

variable "paused" {
  description = "Whether to pause the reconciler and event subscriptions"
  type        = bool
  default     = false
}

# PR-specific variables

variable "pr_priority" {
  description = "Priority for PR events in the workqueue"
  type        = number
  default     = 200
}

variable "own_prs_only" {
  description = <<EOD
Scope the PR-event subscription to PRs this reconciler authored — those on
branches named "<octo_sts_identity>/..." (changemanager's convention). The push
listener has its own subscription, which this does not affect.

Defaults true, since most reconcilers only act on their own PRs. Set false for
reconcilers that act on PRs they did NOT author — e.g. those running in a review
or config mode — since scoping to own branches would hide the very PRs they
exist to review.
EOD
  type        = bool
  default     = true
}

# Dashboard variables

variable "dashboard_labels" {
  description = "Additional labels for the dashboard"
  type        = map(string)
  default     = {}
}

variable "enable_dead_letter_alerting" {
  description = "Whether to enable alerting for dead-lettered keys."
  type        = bool
  default     = true
}

variable "dashboard_alerts" {
  description = "Alert configurations for the dashboard"
  type        = any
  default     = {}
}

variable "launch_stage" {
  description = "The launch stage of the Cloud Run service (e.g. BETA to leverage features like disk volumes)."
  type        = string
  default     = "GA"
}

variable "microvm" {
  description = "Add the microvm dashboard sections (control-plane + agent-pod metrics). The agent-pod section is scoped to the reconciler's octo-sts identity, which by convention equals the GKE namespace its microvm agents run in. Requires octo_sts_identity to be set."
  type        = bool
  default     = false
  validation {
    condition     = !var.microvm || var.octo_sts_identity != ""
    error_message = "octo_sts_identity must be set when microvm is true (the agent namespace matches it)."
  }
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
