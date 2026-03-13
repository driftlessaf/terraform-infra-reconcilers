/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

# Regional Go reconciler for processing GitHub paths
module "reconciler" {
  source = "../github-path-reconciler"

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

  notification_channels       = var.notification_channels
  deletion_protection         = var.deletion_protection
  enable_dead_letter_alerting = var.enable_dead_letter_alerting

  # Path reconciler configuration
  path_patterns     = var.path_patterns
  github_owner      = var.github_owner
  github_repo       = var.github_repo
  octo_sts_identity = var.octo_sts_identity

  resync_period_hours = var.resync_period_hours
  broker              = var.broker
  paused              = var.paused
}

# CloudEvents to Workqueue bridge for pull request events
module "cloudevents-prs" {
  count  = !var.paused ? 1 : 0
  source = "../cloudevents-workqueue"

  project_id = var.project_id
  name       = "${var.name}-pr"
  regions    = var.regions

  broker = var.broker
  filters = [{
    "subject" = "${var.github_owner}/${var.github_repo}"
  }]

  # Use pull request URL as the workqueue key
  extension_key = "pullrequesturl"

  # Send to the reconciler's workqueue
  workqueue = module.reconciler.receiver

  priority = var.pr_priority

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
    github = true
    agents = true
  }

  labels = merge({
    "${var.name}" : ""
    "github" : ""
    "team" : var.team
    "product" : var.product
  }, var.dashboard_labels)

  alerts                = var.dashboard_alerts
  notification_channels = var.notification_channels
}
