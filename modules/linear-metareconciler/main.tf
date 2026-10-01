/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

terraform {
  required_providers {
    ko     = { source = "ko-build/ko" }
    cosign = { source = "chainguard-dev/cosign" }
    # Declare transitive providers so test mocks attach at this module's root.
    google      = { source = "hashicorp/google" }
    google-beta = { source = "hashicorp/google-beta" }
  }
}

# Regional Go reconciler for processing Linear issues and comments
module "reconciler" {
  source             = "../regional-go-reconciler"
  observability_role = var.observability_role

  project_id      = var.project_id
  name            = var.name
  regions         = var.regions
  primary-region  = var.primary-region
  service_account = var.service_account
  team            = var.team
  product         = var.product
  egress          = var.egress

  # Workqueue configuration
  mode            = var.mode
  concurrent-work = var.concurrent-work
  max-retry       = var.max-retry

  # Long mode only: the reconciler runs as a Cloud Run Job per dispatch tick.
  job_timeout  = var.job_timeout
  claim_window = var.claim_window
  claim_poll   = var.claim_poll

  # Container configuration
  containers = var.containers

  request_timeout_seconds = var.request_timeout_seconds
  launch_stage            = var.launch_stage

  notification_channels       = var.notification_channels
  deletion_protection         = var.deletion_protection
  error_event_ingress         = var.error_event_ingress
  trace_event_ingress         = var.trace_event_ingress
  resource_manager_tags       = var.resource_manager_tags
  retain_bucket_admin_binding = var.retain_bucket_admin_binding
}

# CloudEvents to Workqueue bridge for issue events
module "cloudevents-issues" {
  source             = "../cloudevents-workqueue"
  observability_role = var.observability_role

  project_id = var.project_id
  name       = "${var.name}-ce"
  regions    = var.regions

  broker  = var.broker
  filters = var.issue_filters

  # Use issue UUID as the workqueue key (extension set by linear-events trampoline)
  extension_key = "issueid"

  # Send to the reconciler's workqueue
  workqueue = module.reconciler.receiver

  priority = var.issue_priority

  notification_channels = var.notification_channels
  deletion_protection   = var.deletion_protection

  depends_on = [module.reconciler]

  team    = var.team
  product = var.product

  resource_manager_tags = var.resource_manager_tags
}

# CloudEvents to Workqueue bridge for comment events (optional)
module "cloudevents-comments" {
  count              = length(var.comment_filters) > 0 ? 1 : 0
  source             = "../cloudevents-workqueue"
  observability_role = var.observability_role

  project_id = var.project_id
  name       = "${var.name}-cmt"
  regions    = var.regions

  broker  = var.broker
  filters = var.comment_filters
  filter_not = [
    for id in var.comment_skip_authors : { key = "authorid", value = id }
  ]

  # Comments use the parent issue UUID as the workqueue key
  extension_key = "issueid"

  # Send to the reconciler's workqueue
  workqueue = module.reconciler.receiver

  priority = var.comment_priority

  notification_channels = var.notification_channels
  deletion_protection   = var.deletion_protection

  depends_on = [module.reconciler]

  team    = var.team
  product = var.product

  resource_manager_tags = var.resource_manager_tags
}

# Dashboard for monitoring the reconciler
module "dashboard" {
  source = "../dashboard/reconciler"

  project_id      = var.project_id
  name            = var.name
  max_retry       = var.max-retry
  concurrent_work = var.concurrent-work
  mode            = var.mode

  sections = {
    agents = true
  }

  labels = merge({
    (var.name) : ""
    "linear" : ""
    "team" : var.team
    "product" : var.product
  }, var.dashboard_labels)

  alerts                = var.dashboard_alerts
  notification_channels = var.notification_channels
}
