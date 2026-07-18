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
  dead_letter_alert_threshold = var.dead_letter_alert_threshold
  dead_letter_alert_duration  = var.dead_letter_alert_duration
  receiver_ingress            = var.receiver_ingress
  error_event_ingress         = var.error_event_ingress
  trace_event_ingress         = var.trace_event_ingress
  // In short mode, derive the name from module.reconciler so dispatcher-calls-target
  // implicitly waits for the reconciler Cloud Run service to exist. The value is
  // identical to "${var.name}-rec" (regional-go-service uses var.name verbatim) —
  // it's the dependency we want, not the string.
  reconciler_service_name = var.mode == "short" ? values(module.reconciler[0].names)[0] : "${var.name}-rec"
  cpu_idle                = var.workqueue_cpu_idle

  receiver_service_name   = "${var.name}-wq-rcv"
  dispatcher_service_name = "${var.name}-wq-dsp"
  reenqueue_job_name      = "${var.name}-wq-req"

  dispatcher_batch_size = var.batch-size != null ? var.batch-size : ceil(var.concurrent-work / length(var.regions))
  reenqueue_region      = coalesce(var.primary-region, keys(var.regions)[0])

  dispatcher_sa_email       = var.service_account
  additional_bucket_members = ["serviceAccount:${var.service_account}"]
  dlq_operator_members      = var.dlq_operators
  reenqueue_invokers        = var.reenqueue_invokers

  // When shards > 1 the inline workqueue (bucket, receiver, dispatcher,
  // reenqueue, alerts) is replaced by hyperqueue instances.
  workqueue_enabled = var.shards == 1

  // In long mode the PubSub change trigger is replaced by the per-minute cron.
  dispatcher_change_trigger_enabled = var.mode == "short" && local.workqueue_enabled
  // In long mode the HTTP-based cron trigger is replaced by a job invocation.
  dispatcher_cron_enabled = var.mode == "short" && local.workqueue_enabled
  // In long mode the reconciler is a Job, not a Service, so no run.invoker grant.
  dispatcher_calls_target_enabled = var.mode == "short" && local.workqueue_enabled
  // In long mode the dispatcher runs inside the Cloud Run Job, not a standalone service.
  dispatcher_service_enabled = var.mode == "short" && local.workqueue_enabled
}
