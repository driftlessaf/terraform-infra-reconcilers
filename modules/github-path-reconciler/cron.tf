/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

locals {
  # The cron fires every resync_floor_hours; each firing enqueues only the
  # shard of keys assigned to that tick of each repo's resync period.
  cron_schedule = "0 */${var.resync_floor_hours} * * *"
  # Tick (= shard size = floor) in minutes — the unit the resync sharder
  # works in. Per-repo resync periods are sourced from var.repos and
  # .{identity}.yaml.
  tick_minutes = var.resync_floor_hours * 60
}

module "cron" {
  source = "chainguard-dev/common/infra//modules/cron"

  name       = "${var.name}-enq"
  project_id = var.project_id
  region     = var.primary-region

  importpath  = "./cmd/resync"
  working_dir = path.module

  service_account = var.service_account
  # The resync cron shares the reconciler's service account; the reconciler
  # components own its observability grants. A second granting resource here
  # would revoke them for the reconciler when this cron is destroyed.
  enable_observability_iam = false
  schedule                 = local.cron_schedule
  paused                   = var.paused

  env = merge({
    OCTO_STS_IDENTITY = var.octo_sts_identity
    OCTO_IDENTITY     = var.octo_sts_identity
    WORKQUEUE_ADDR    = module.authorize-receiver-per-region[var.primary-region].uri
    REPOS_CONFIG      = jsonencode(var.repos)
    TICK_MINUTES      = tostring(local.tick_minutes)
    },
    var.github_app_id != 0 ? {
      GITHUB_APP_ID  = tostring(var.github_app_id)
      GITHUB_APP_KEY = var.github_app_key
    } : {}
  )

  vpc_access = {
    network_interfaces = [{
      network    = var.regions[var.primary-region].network
      subnetwork = var.regions[var.primary-region].subnet
    }]
    egress = "PRIVATE_RANGES_ONLY"
  }

  notification_channels = var.notification_channels
  deletion_protection   = var.deletion_protection
  labels                = var.labels
  team                  = var.team
  product               = var.product
  resource_manager_tags = var.resource_manager_tags
  version               = "1.37.3"
}
