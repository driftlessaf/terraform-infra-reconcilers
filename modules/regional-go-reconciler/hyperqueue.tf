/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

// Stand up the sharded workqueue infrastructure (shards > 1). This replaces
// the inline workqueue resources (gated off via local.workqueue_enabled)
// with N independent workqueues behind a hyperqueue router; the module's
// receiver output points at the router so enqueuers are unaffected.
module "workqueue-sharded" {
  count  = var.shards > 1 ? 1 : 0
  source = "../workqueue/hyperqueue"

  project_id         = var.project_id
  observability_role = var.observability_role
  name               = "${var.name}-wq"
  regions            = var.regions
  shards             = var.shards

  concurrent-work             = var.concurrent-work
  batch-size                  = var.batch-size
  max-retry                   = var.max-retry
  enable_dead_letter_alerting = var.enable_dead_letter_alerting

  // Threading the name through local.reconciler_service_name makes the
  // shard dispatchers wait for the reconciler Cloud Run service to exist.
  reconciler-service = {
    name = local.reconciler_service_name
  }

  team                  = var.team
  product               = var.product
  deletion_protection   = var.deletion_protection
  notification_channels = var.notification_channels
  labels                = var.labels

  multi_regional_location = var.multi_regional_location

  error_event_ingress = var.error_event_ingress

  resource_manager_tags = var.resource_manager_tags
}
