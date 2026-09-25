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

variable "regional-connector" {
  type        = map(string)
  description = <<EOD
Forwarded to the receiver and dispatcher services (regional-go-service) and the
reenqueue job (cron). Optional per-region Serverless VPC Access connector,
keyed by region name, as a fully qualified id
projects/<project>/locations/<region>/connectors/<name>. A region present here
egresses through the connector instead of direct VPC egress — either because
Cloud NAT does not translate direct VPC egress from a Shared-VPC service
project, or to amortize network-interface provisioning across instances
instead of allocating one per instance/revision. Declared identically here and
in regional-go-reconciler's variables.tf because dispatcher-service.tf,
receiver.tf, and reenqueue.tf are shared files between the two modules.
EOD
  default     = {}
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

variable "candidate-window-factor" {
  description = "How far each dispatch pass shuffles its candidates, as a multiple of the keys that pass can launch (window = factor x launch slots). Any whole number is valid, there are no special steps. 0 disables the shuffle: every dispatcher takes the head of the queue, so dispatchers sharing a queue race for the same keys and lose most contested claims. Raising it spreads dispatchers over more keys, lowering lost claims, at the cost of how long a key can sit unpicked (up to the factor in passes when only one dispatcher is running). Measured with three dispatchers, lost-claim share of the slowest: 16 -> 11.2%, 24 -> 8.0%, 32 -> 6.5%, 48 -> 4.2%, 64 -> 3.4%. 48 is the smallest that keeps the slowest dispatcher under 5% and is the library default (dispatcher.DefaultCandidateWindowFactor); the module defaults to 0 so spreading is opt-in per environment. Go lower only if pick latency matters more than contention, higher only if loss is still high with more dispatchers. Above about 96 the window reaches the enumeration limit and larger values change nothing, so the input is capped at 128."
  type        = number
  default     = 0

  validation {
    condition     = var.candidate-window-factor >= 0 && var.candidate-window-factor <= 128 && var.candidate-window-factor == floor(var.candidate-window-factor)
    error_message = "candidate-window-factor must be a whole number from 0 to 128. 0 disables spreading; 48 is the measured recommendation; values above about 96 have no additional effect because the window is clipped to the enumerated list."
  }
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

variable "retain_bucket_admin_binding" {
  description = <<-EOT
    Keep the roles/storage.admin binding on the workqueue bucket. True (the
    default) is the access this module has always granted. False drops it,
    leaving the receiver, dispatcher and additional_bucket_members on the
    additive roles/storage.objectUser grants, which is everything the queue
    actually uses.

    It exists so the reduction can be taken one deployment at a time —
    dev, then staging, then production — rather than reaching every caller of
    this module on whichever apply runs first. Flipping it is the only step
    that revokes anything. A later release removes both the binding and this
    variable, so treat false as the destination rather than a supported
    configuration.
  EOT
  type        = bool
  default     = true
  nullable    = false
}
