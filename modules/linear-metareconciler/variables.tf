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

variable "issue_filters" {
  description = <<EOD
CloudEvents filters for selecting Linear issue events to process.

Each filter is a map of attribute key-value pairs that must match exactly.
Multiple filters are combined with OR logic.

Examples:
  # All issue events
  issue_filters = [
    { "type" = "dev.chainguard.linear.issue" }
  ]

  # Issue events from a specific team
  issue_filters = [
    { "type" = "dev.chainguard.linear.issue", "team" = "ENG" }
  ]
EOD
  type        = list(map(string))
  default     = [{ "type" = "dev.chainguard.linear.issue" }]
}

variable "comment_filters" {
  description = <<EOD
CloudEvents filters for selecting Linear comment events to process.

Comment events carry a `team` extension extracted from the embedded issue
URL by the linear-events trampoline, so they can be filtered by team the
same way as issue events.

Examples:
  # All comment events
  comment_filters = [
    { "type" = "dev.chainguard.linear.comment" }
  ]

  # Comment events from a specific team
  comment_filters = [
    { "type" = "dev.chainguard.linear.comment", "team" = "ENG" }
  ]
EOD
  type        = list(map(string))
  default     = []
}

variable "containers" {
  description = "The containers to run in the service."
  type = map(object({
    source = object({
      base_image  = optional(string, "cgr.dev/chainguard/static:latest-glibc@sha256:11ec91f0372630a2ca3764cea6325bebb0189a514084463cbb3724e5bb350d14")
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

variable "comment_priority" {
  description = "Priority for comment events in the workqueue"
  type        = number
  default     = 25
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
