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

variable "filters" {
  description = "CloudEvents filters for selecting events to process (applied to both issue and PR events)"
  type        = list(map(string))
  default     = []
}

variable "containers" {
  description = "The containers to run in the service."
  type = map(object({
    source = object({
      base_image  = optional(string, "cgr.dev/chainguard/static:latest-glibc@sha256:a301031ffd4ed67f35ca7fa6cf3dad9937b5fa47d7493955a18d9b4ca5412d1a")
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
  default     = 50
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
