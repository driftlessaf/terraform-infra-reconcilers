variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "name" {
  description = "The base name for resources"
  type        = string
}

variable "regions" {
  description = "A map of regions to launch services in (see regional-go-service module for format)"
  type = map(object({
    network = string
    subnet  = string
  }))
}

variable "broker" {
  type        = map(string)
  description = "A map from each of the input region names to the name of the Broker topic in that region."
}

variable "filters" {
  description = <<EOD
A list of Knative Trigger-style filters over cloud event attributes.

Each filter is a map of attribute key-value pairs that must match exactly.
Multiple filters are combined with OR logic (any filter can match).

Examples:
  # Single event type
  filters = [
    { "type" = "dev.chainguard.github.pull_request" }
  ]

  # Multiple event types
  filters = [
    { "type" = "dev.chainguard.github.pull_request" },
    { "type" = "dev.chainguard.github.pull_request_review" }
  ]

  # Filter by type and action
  filters = [
    {
      "type"   = "dev.chainguard.github.pull_request"
      "action" = "opened"
    }
  ]
EOD
  type        = list(map(string))
  default     = []
}

variable "filter_prefix" {
  description = <<EOD
Knative Trigger-style prefix clauses AND-composed with each per-trigger
positive filter from `filters`. Each entry produces a
`hasPrefix(attributes.ce-<key>, "<value>")` clause. For example, to
receive only PRs on branches a reconciler owns (its PR branches are named
"<identity>/..."):

  filter_prefix = { headbranch = "my-reconciler/" }
EOD
  type        = map(string)
  default     = {}
}

variable "filter_prefixes" {
  description = <<EOD
Alternative to `filter_prefix` for matching any one of several prefix sets.
A Pub/Sub filter AND-composes its clauses, so prefixes that should match as
an OR cannot share a trigger; each entry here gets its own trigger per
positive filter from `filters`. Use this to serve more than one branch
namespace from a single reconciler:

  filter_prefixes = [
    { headbranch = "my-reconciler/" },
    { headbranch = "other-reconciler/" },
  ]

Mutually exclusive with `filter_prefix`.
EOD
  type        = list(map(string))
  default     = []

  validation {
    condition     = length(var.filter_prefixes) == 0 || length(var.filter_prefix) == 0
    error_message = "Set filter_prefix or filter_prefixes, not both."
  }
}

variable "filter_not" {
  description = <<EOD
Negative-equality clauses AND-composed with each per-trigger positive
filter from `filters` (i.e. layered on top of every trigger this module
creates, not a separate trigger of their own). Each entry produces a
`NOT attributes.ce-<key>="<value>"` clause. Use a list (not a map) so
the same key can appear multiple times — e.g. to skip events from
several authors:

  filter_not = [
    { key = "authorid", value = "user-uuid-1" },
    { key = "authorid", value = "user-uuid-2" },
  ]
EOD
  type = list(object({
    key   = string
    value = string
  }))
  default = []
}

variable "extension_key" {
  description = "The CloudEvent extension attribute to use as the workqueue key (e.g., pullrequesturl or issueurl)"
  type        = string
}

variable "workqueue" {
  description = "The workqueue to send events to"
  type = object({
    name = string
  })
}

variable "notification_channels" {
  description = "List of notification channels for alerts"
  type        = list(string)
}



variable "team" {
  description = "Team label to apply to resources (replaces deprecated 'squad')."
  type        = string
}

variable "max_delivery_attempts" {
  description = "The maximum number of delivery attempts for any event."
  type        = number
  default     = 20
}

variable "minimum_backoff" {
  description = "The minimum delay between consecutive deliveries of a given message."
  type        = number
  default     = 10
}

variable "maximum_backoff" {
  description = "The maximum delay between consecutive deliveries of a given message."
  type        = number
  default     = 600
}

variable "ack_deadline_seconds" {
  description = "The deadline for acking a message."
  type        = number
  default     = 300
}

variable "product" {
  description = "Product label to apply to the service."
  type        = string
  default     = "unknown"
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection for resources"
  type        = bool
  default     = true
}

variable "priority" {
  description = "Priority for workqueue items (higher values = higher priority)"
  type        = number
  default     = 0
}

variable "delay_seconds" {
  description = "Minimum delay (in seconds) before an enqueued key becomes eligible for processing, so bursts of events for the same key coalesce into ~one reconcile per window. 0 disables it."
  type        = number
  default     = 0
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
