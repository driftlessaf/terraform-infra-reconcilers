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
  dead_letter_alert_threshold = var.dead_letter_alert_threshold
  dead_letter_alert_duration  = var.dead_letter_alert_duration
  receiver_ingress            = var.receiver_ingress
  error_event_ingress         = var.error_event_ingress
  reconciler_service_name     = var.reconciler-service.name
  cpu_idle                    = var.cpu_idle

  receiver_service_name   = "${var.name}-rcv"
  dispatcher_service_name = "${var.name}-dsp"
  reenqueue_job_name      = "${var.name}-req"

  dispatcher_batch_size = var.batch-size != null ? var.batch-size : ceil(var.concurrent-work / length(var.regions))
  reenqueue_region      = coalesce(var.primary-region, keys(var.regions)[0])

  // dispatcher_sa_email is the identity that calls the reconciler and error broker.
  // In standalone mode this is the dispatcher's dedicated SA; modules that inline
  // the dispatcher as a sidecar override this with their own service account.
  dispatcher_sa_email = google_service_account.dispatcher[0].email

  // additional_bucket_members are extra IAM members granted storage.admin on
  // the workqueue bucket.  Inline deployments set this to their service account.
  additional_bucket_members = []

  // dlq_operator_members are IAM members granted roles/storage.objectAdmin for
  // dead-letter queue operations. Inline deployments override this via var.dlq_operators.
  dlq_operator_members = []

  // reenqueue_invokers are IAM members granted roles/run.invoker on the reenqueue
  // job. The regional-go-reconciler wrapper overrides this via var.reenqueue_invokers.
  reenqueue_invokers = []

  // reenqueue_schedule/reenqueue_paused control the dead-letter reenqueue cron.
  // The bare workqueue keeps the historical manual-only behavior: paused, with a
  // placeholder schedule that never fires. The regional-go-reconciler wrapper
  // overrides these via var.reenqueue_schedule to opt into periodic auto-drain.
  reenqueue_schedule = "0 0 * * *"
  reenqueue_paused   = true

  // workqueue_enabled controls whether this module's workqueue resources
  // (bucket, receiver, dispatcher, reenqueue, alerts) are created.  The
  // regional-go-reconciler wrapper sets this false when shards > 1 delegates
  // the workqueue to hyperqueue instances instead.
  workqueue_enabled = true

  // dispatcher_change_trigger_enabled controls whether the PubSub object-change
  // subscription and its supporting resources are created.  Set to false in
  // "long" mode where a cron-driven job replaces the event-triggered service.
  dispatcher_change_trigger_enabled = true

  // dispatcher_cron_enabled controls whether the HTTP-based cron trigger that
  // calls the dispatcher service is created.  Set to false in "long" mode.
  dispatcher_cron_enabled = true

  // dispatcher_calls_target_enabled controls whether the dispatcher is granted
  // run.invoker on the reconciler Cloud Run Service.  Set to false in "long"
  // mode where the reconciler is a Job, not a Service.
  dispatcher_calls_target_enabled = true

  // dispatcher_service_enabled controls whether the standalone dispatcher
  // Cloud Run Service is created.  Set to false in "long" mode where the
  // dispatcher runs as a container inside a Cloud Run Job instead.
  dispatcher_service_enabled = true
}
