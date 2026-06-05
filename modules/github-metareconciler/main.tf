/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

# Regional Go reconciler for processing GitHub issues and PRs
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
  filters = var.filters

  # Use issue URL as the workqueue key
  extension_key = "issueurl"

  # Send to the reconciler's workqueue
  workqueue = module.reconciler.receiver

  priority = var.issue_priority

  notification_channels = var.notification_channels
  deletion_protection   = var.deletion_protection

  depends_on = [module.reconciler]

  team = var.team
}

# CloudEvents to Workqueue bridge for pull request events
module "cloudevents-prs" {
  source = "../cloudevents-workqueue"

  project_id = var.project_id
  name       = "${var.name}-pr"
  regions    = var.regions

  broker  = var.broker
  filters = var.filters

  # When own_prs_only is set, deliver only PR events for branches this reconciler
  # authored (changemanager names them "<octo_sts_identity>/..."). Applied to PR
  # events only — the cloudevents-issues subscription above must not get a
  # headbranch filter, since issue events carry no headbranch attribute.
  filter_prefix = var.own_prs_only ? { headbranch = "${var.octo_sts_identity}/" } : {}

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
