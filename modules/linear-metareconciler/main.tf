/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

# Regional Go reconciler for processing Linear issues and comments
module "reconciler" {
  source = "../regional-go-reconciler"

  project_id      = var.project_id
  name            = var.name
  regions         = var.regions
  primary-region  = var.primary-region
  service_account = var.service_account
  team            = var.team
  product         = var.product
  egress          = var.egress

  # Workqueue configuration
  concurrent-work = var.concurrent-work
  max-retry       = var.max-retry

  # Container configuration
  containers = var.containers

  request_timeout_seconds = var.request_timeout_seconds
  launch_stage            = var.launch_stage

  notification_channels = var.notification_channels
  deletion_protection   = var.deletion_protection
  error_event_ingress   = var.error_event_ingress
}

# CloudEvents to Workqueue bridge for issue events
module "cloudevents-issues" {
  source = "../cloudevents-workqueue"

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

  team = var.team
}

# CloudEvents to Workqueue bridge for comment events (optional)
module "cloudevents-comments" {
  count  = length(var.comment_filters) > 0 ? 1 : 0
  source = "../cloudevents-workqueue"

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

  team = var.team
}

# Dashboard for monitoring the reconciler
module "dashboard" {
  source = "../dashboard/reconciler"

  project_id      = var.project_id
  name            = var.name
  max_retry       = var.max-retry
  concurrent_work = var.concurrent-work

  sections = {
    agents = true
  }

  labels = merge({
    "${var.name}" : ""
    "linear" : ""
    "team" : var.team
    "product" : var.product
  }, var.dashboard_labels)

  alerts                = var.dashboard_alerts
  notification_channels = var.notification_channels
}
