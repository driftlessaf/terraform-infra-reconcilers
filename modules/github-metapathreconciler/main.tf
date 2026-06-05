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

  mode                    = var.mode
  job_timeout             = var.job_timeout
  request_timeout_seconds = var.request_timeout_seconds
  launch_stage            = var.launch_stage

  notification_channels       = var.notification_channels
  deletion_protection         = var.deletion_protection
  enable_dead_letter_alerting = var.enable_dead_letter_alerting

  # Path reconciler configuration
  repos             = var.repos
  octo_sts_identity = var.octo_sts_identity
  github_app_id     = var.github_app_id
  github_app_key    = var.github_app_key

  resync_floor_hours  = var.resync_floor_hours
  broker              = var.broker
  paused              = var.paused
  error_event_ingress = var.error_event_ingress
}

# CloudEvents to Workqueue bridge for pull request events
module "cloudevents-prs" {
  count  = !var.paused ? 1 : 0
  source = "../cloudevents-workqueue"

  project_id = var.project_id
  name       = "${var.name}-pr"
  regions    = var.regions

  broker = var.broker
  # When repos is non-empty, filter triggers to matching repo subjects.
  # When repos is empty (e.g. push/resync disabled), use an unfiltered trigger
  # so PR events still flow. The cloudevents-workqueue module's
  # filter_has_attributes check on "pullrequesturl" ensures only PR events
  # actually reach the workqueue.
  filters = length(var.repos) > 0 ? [for r in var.repos : { "subject" = "${r.owner}/${r.repo}" }] : [{}]

  # When own_prs_only is set, deliver only PR events for branches this reconciler
  # authored (changemanager names them "<octo_sts_identity>/...").
  filter_prefix = var.own_prs_only ? { headbranch = "${var.octo_sts_identity}/" } : {}

  # Use pull request URL as the workqueue key
  extension_key = "pullrequesturl"

  # Send to the reconciler's workqueue
  workqueue = module.reconciler.receiver

  priority = var.pr_priority

  notification_channels = var.notification_channels
  deletion_protection   = var.paused

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
