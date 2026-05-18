/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

locals {
  sa_prefix = "${var.name}-wq-"

  default_labels = {
    workqueue        = "${var.name}-wq"
    terraform-module = "workqueue"
  }

  squad_label = {
    squad = var.team
    team  = var.team
  }
  product_label = var.product != "" ? {
    product = var.product
  } : {}

  merged_labels = merge(local.default_labels, local.squad_label, local.product_label, var.labels)

  name                        = "${var.name}-wq"
  project_id                  = var.project_id
  regions                     = var.regions
  team                        = var.team
  product                     = var.product
  notification_channels       = var.notification_channels
  deletion_protection         = var.deletion_protection
  multi_regional_location     = var.multi_regional_location
  concurrent_work             = var.concurrent-work
  max_retry                   = var.max-retry
  enable_dead_letter_alerting = var.enable_dead_letter_alerting
  receiver_ingress            = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  error_event_ingress         = var.error_event_ingress
  reconciler_service_name     = "${var.name}-rec"
  cpu_idle                    = var.workqueue_cpu_idle

  receiver_service_name   = "${var.name}-wq-rcv"
  dispatcher_service_name = "${var.name}-wq-dsp"
  reenqueue_job_name      = "${var.name}-wq-req"

  dispatcher_batch_size = var.batch-size != null ? var.batch-size : ceil(var.concurrent-work / length(var.regions))
  reenqueue_region      = coalesce(var.primary-region, keys(var.regions)[0])
}
