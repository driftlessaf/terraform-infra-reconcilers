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

variable "concurrent-work" {
  description = "The amount of concurrent work to dispatch at a given time."
  type        = number
}

variable "batch-size" {
  description = "Optional cap on how much work to launch per dispatcher pass. Defaults to ceil(concurrent-work / number of regions) when unset."
  type        = number
  default     = null
}

variable "max-retry" {
  description = "The maximum number of retry attempts before a task is moved to the dead letter queue. Set this to 0 to have unlimited retries."
  type        = number
  nullable    = false
  default     = 20
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

variable "reconciler-service" {
  description = "The name of the reconciler service that the workqueue will dispatch work to."
  type = object({
    name = string
  })
}

variable "team" {
  description = "Team label to apply to resources (replaces deprecated 'squad')."
  type        = string
}

variable "deletion_protection" {
  type        = bool
  description = "Whether to enable delete protection for the service."
  default     = true
}

variable "enable_observability_iam" {
  type        = bool
  default     = true
  description = "Whether the dispatcher service grants its service account the observability roles (monitoring.metricWriter, cloudtrace.agent, cloudprofiler.agent) on the project. Set false only when the caller manages those grants for the dispatcher's service account itself; the standalone workqueue dispatcher runs as a dedicated service account, so the default true is correct there."
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

variable "scope" {
  description = "The scope of the workqueue. Must be 'global' for a single multi-regional workqueue."
  type        = string
  default     = "global"

  validation {
    condition     = var.scope == "global"
    error_message = "scope must be 'global'. Regional scope is no longer supported."
  }
}

variable "multi_regional_location" {
  description = "The multi-regional location for the global workqueue bucket (e.g., 'US', 'EU', 'ASIA'). Only used when scope='global'."
  type        = string
  default     = "US"

  validation {
    condition     = contains(["US", "EU", "ASIA"], var.multi_regional_location)
    error_message = "multi_regional_location must be one of 'US', 'EU', or 'ASIA'."
  }
}

variable "cpu_idle" {
  description = "Set to false for a region in order to use instance-based billing. Defaults to true."
  type        = map(map(bool))
  default = {
    "dispatcher" = {}
    "receiver"   = {}
  }
}

variable "receiver_ingress" {
  type        = string
  description = "The ingress traffic setting for the workqueue receiver service. INGRESS_TRAFFIC_ALL allows callers outside the VPC (e.g. Cloud Run services without VPC egress) to enqueue work."
  default     = "INGRESS_TRAFFIC_INTERNAL_ONLY"
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
