locals {
  sa_prefix = "${var.name}-"

  default_labels = {
    basename(abspath(path.module)) = var.name
    terraform-module               = basename(abspath(path.module))
  }

  squad_label = {
    squad = var.team
    team  = var.team
  }
  product_label = var.product != "" ? {
    product = var.product
  } : {}

  merged_labels = merge(local.default_labels, local.squad_label, local.product_label, var.labels)

  name                        = var.name
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
  receiver_ingress            = var.receiver_ingress
  error_event_ingress         = var.error_event_ingress
  reconciler_service_name     = var.reconciler-service.name
  cpu_idle                    = var.cpu_idle

  receiver_service_name   = "${var.name}-rcv"
  dispatcher_service_name = "${var.name}-dsp"
  reenqueue_job_name      = "${var.name}-req"

  dispatcher_batch_size = var.batch-size != null ? var.batch-size : ceil(var.concurrent-work / length(var.regions))
  reenqueue_region      = coalesce(var.primary-region, keys(var.regions)[0])
}
