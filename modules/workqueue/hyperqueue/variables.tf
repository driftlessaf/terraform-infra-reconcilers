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
  description = "A map from region names to a network and subnetwork."
  type = map(object({
    network = string
    subnet  = string
  }))
}

variable "shards" {
  description = "Number of workqueue shards (2-5). Each shard is an independent workqueue."
  type        = number
  default     = 2

  validation {
    condition     = var.shards >= 2 && var.shards <= 5
    error_message = "shards must be between 2 and 5"
  }
}

variable "concurrent-work" {
  description = "The amount of concurrent work to dispatch at a given time (distributed across shards)."
  type        = number
}

variable "regional-concurrent-work" {
  description = "Optional cap on concurrent work in each dispatcher region, distributed across shards. Must be a positive integer when set. The global concurrent-work cap also applies."
  type        = number
  default     = null

  validation {
    condition     = var.regional-concurrent-work == null ? true : var.regional-concurrent-work > 0 && floor(var.regional-concurrent-work) == var.regional-concurrent-work
    error_message = "regional-concurrent-work must be a positive integer when set."
  }
}

check "regional_concurrency_per_shard" {
  assert {
    condition     = var.regional-concurrent-work == null || var.regional-concurrent-work >= var.shards
    error_message = "regional-concurrent-work must be at least the number of shards."
  }
}

variable "batch-size" {
  description = "Optional cap on how much work to launch per dispatcher pass."
  type        = number
  default     = null
}

variable "max-retry" {
  description = "The maximum number of retry attempts before a task is moved to the dead letter queue."
  type        = number
  nullable    = false
  default     = 20
}

variable "scheduled_wait_warning_threshold" {
  description = "Duration after which a shard dispatcher claiming an eligible GCS workqueue key emits a structured warning (for example, \"1h\"). Set to \"0s\" to disable."
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

variable "enable_dead_letter_alerting" {
  description = "Whether to enable alerting for dead-lettered keys."
  type        = bool
  default     = true
}

variable "reconciler-service" {
  description = "The name of the reconciler service that the workqueue will dispatch work to."
  type = object({
    name = string
  })
}

variable "team" {
  description = "Team label to apply to resources."
  type        = string
}

variable "deletion_protection" {
  type        = bool
  description = "Whether to enable delete protection for the service."
  default     = true
}

variable "notification_channels" {
  description = "List of notification channels to alert."
  type        = list(string)
}

variable "labels" {
  description = "Labels to apply to the workqueue resources."
  type        = map(string)
  default     = {}
}

variable "product" {
  description = "Product label to apply to the service."
  type        = string
  default     = "unknown"
}

variable "multi_regional_location" {
  description = "The multi-regional location for the workqueue buckets."
  type        = string
  default     = "US"

  validation {
    condition     = contains(["US", "EU", "ASIA"], var.multi_regional_location)
    error_message = "multi_regional_location must be one of 'US', 'EU', or 'ASIA'."
  }
}

variable "error_event_ingress" {
  description = "Optional CloudEvents ingress for emitting reconciler error events. Set to null to disable."
  type = object({
    name = string
  })
  default = null
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
  description = "Resource Manager tags forwarded to every shard workqueue and to the hyperqueue router service, as tagKeys/<id> => tagValues/<id>."
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
