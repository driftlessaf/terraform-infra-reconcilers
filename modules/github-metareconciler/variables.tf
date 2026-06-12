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

variable "filters" {
  description = "CloudEvents filters for selecting events to process (applied to both issue and PR events)"
  type        = list(map(string))
  default     = []
}

variable "containers" {
  description = "The containers to run in the service."
  type = map(object({
    source = object({
      base_image  = optional(string, "cgr.dev/chainguard/static:latest-glibc@sha256:2fdfacc8d61164aa9e20909dceec7cc28b9feb66580e8e1a65b9f2443c53b61b")
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

variable "issue_priority" {
  description = "Priority for issue events in the workqueue"
  type        = number
  default     = 50
}

variable "pr_priority" {
  description = "Priority for PR events in the workqueue"
  type        = number
  default     = 200
}

variable "octo_sts_identity" {
  description = <<EOD
The reconciler's octo-sts identity (the same value passed to the binary as
OCTO_IDENTITY). Used only to scope PR events when own_prs_only is set, since
changemanager names this reconciler's branches "<octo_sts_identity>/...".
Filter-only here: unlike github-metapathreconciler this module wires no auth to
it (the binary handles GitHub auth itself).
EOD
  type        = string
  default     = ""
  validation {
    condition     = !var.own_prs_only || var.octo_sts_identity != ""
    error_message = "octo_sts_identity must be set when own_prs_only is true."
  }
}

variable "own_prs_only" {
  description = <<EOD
Scope the PR-event subscription to PRs this reconciler authored — those on
branches named "<octo_sts_identity>/...". Never affects the issues subscription
(issue events carry no headbranch).

Defaults true, since most reconcilers only act on their own PRs. Set false for
reconcilers that act on PRs they did NOT author, since scoping to own branches
would hide those PRs.
EOD
  type        = bool
  default     = true
}

variable "dashboard_labels" {
  description = "Additional labels for the dashboard"
  type        = map(string)
  default     = {}
}

variable "dashboard_alerts" {
  description = "Alert configurations for the dashboard"
  type        = any
  default     = {}
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

variable "request_timeout_seconds" {
  description = "The request timeout for the service in seconds."
  type        = number
  default     = 300
}

variable "team" {
  type        = string
  description = "Team label for the service"
}

variable "product" {
  type        = string
  description = "Product label for the service"
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
