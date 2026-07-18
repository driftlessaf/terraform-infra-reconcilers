// Bucket
moved {
  from = module.workqueue[0].random_string.bucket_suffix
  to   = random_string.bucket_suffix
}
moved {
  from = module.workqueue[0].google_storage_bucket.global-workqueue
  to   = google_storage_bucket.global-workqueue
}
moved {
  from = module.workqueue[0].google_storage_bucket_iam_binding.global-authorize-access
  to   = google_storage_bucket_iam_binding.global-authorize-access
}
moved {
  from = module.workqueue[0].google_pubsub_topic.global-object-change-notifications
  to   = google_pubsub_topic.global-object-change-notifications
}
moved {
  from = module.workqueue[0].google_pubsub_topic_iam_binding.global-gcs-publishes-to-topic
  to   = google_pubsub_topic_iam_binding.global-gcs-publishes-to-topic
}
moved {
  from = module.workqueue[0].google_storage_notification.global-object-change-notifications
  to   = google_storage_notification.global-object-change-notifications
}

// Receiver
moved {
  from = module.workqueue[0].random_string.receiver
  to   = random_string.receiver
}
moved {
  from = module.workqueue[0].google_service_account.receiver
  to   = google_service_account.receiver
}
moved {
  from = module.workqueue[0].module.receiver-service
  to   = module.receiver-service
}

// Dispatcher triggers and service accounts
moved {
  from = module.workqueue[0].random_string.dispatcher
  to   = random_string.dispatcher
}
moved {
  from = module.workqueue[0].google_service_account.dispatcher
  to   = google_service_account.dispatcher
}
moved {
  from = module.workqueue[0].module.dispatcher-calls-target
  to   = module.dispatcher-calls-target
}
moved {
  from = module.workqueue[0].module.dispatcher-calls-error-broker
  to   = module.dispatcher-calls-error-broker
}
// module.workqueue[0].module.dispatcher-service is intentionally not moved —
// the standalone dispatcher service is replaced by the combined reconciler service.
moved {
  from = module.workqueue[0].random_string.cron-trigger
  to   = random_string.cron-trigger
}
moved {
  from = module.workqueue[0].google_service_account.cron-trigger
  to   = google_service_account.cron-trigger
}
moved {
  from = module.workqueue[0].module.cron-trigger-calls-dispatcher
  to   = module.cron-trigger-calls-dispatcher
}
moved {
  from = module.workqueue[0].google_cloud_scheduler_job.cron
  to   = google_cloud_scheduler_job.cron
}
moved {
  from = module.workqueue[0].random_string.change-trigger
  to   = random_string.change-trigger
}
moved {
  from = module.workqueue[0].google_service_account.change-trigger
  to   = google_service_account.change-trigger
}
moved {
  from = module.workqueue[0].google_project_service_identity.pubsub
  to   = google_project_service_identity.pubsub
}
moved {
  from = module.workqueue[0].google_service_account_iam_binding.allow-pubsub-to-mint-tokens
  to   = google_service_account_iam_binding.allow-pubsub-to-mint-tokens
}
moved {
  from = module.workqueue[0].module.change-trigger-calls-dispatcher
  to   = module.change-trigger-calls-dispatcher
}
moved {
  from = module.workqueue[0].google_pubsub_subscription.global-this
  to   = google_pubsub_subscription.global-this
}

// Reenqueue job
moved {
  from = module.workqueue[0].random_string.reenqueue
  to   = random_string.reenqueue
}
moved {
  from = module.workqueue[0].google_service_account.reenqueue
  to   = google_service_account.reenqueue
}
moved {
  from = module.workqueue[0].google_storage_bucket_iam_member.reenqueue-bucket-access
  to   = google_storage_bucket_iam_member.reenqueue-bucket-access
}
moved {
  from = module.workqueue[0].module.reenqueue
  to   = module.reenqueue
}

// Alerts
moved {
  from = module.workqueue[0].google_monitoring_alert_policy.dead_letter_queue
  to   = google_monitoring_alert_policy.dead_letter_queue
}

// module.reconciler now has count = (mode == "short" ? 1 : 0).
// Existing short-mode deployments have state at the bare address; move to [0].
moved {
  from = module.reconciler
  to   = module.reconciler[0]
}

// module.dispatcher-service now has count = (mode == "short" ? 1 : 0).
// Existing short-mode deployments have state at the bare address; move to [0].
moved {
  from = module.dispatcher-service
  to   = module.dispatcher-service[0]
}

// change-trigger resources now have count = (dispatcher_change_trigger_enabled ? 1 : 0).
// Existing short-mode deployments have state at the bare address; move to [0].
moved {
  from = random_string.change-trigger
  to   = random_string.change-trigger[0]
}
moved {
  from = google_service_account.change-trigger
  to   = google_service_account.change-trigger[0]
}
moved {
  from = google_project_service_identity.pubsub
  to   = google_project_service_identity.pubsub[0]
}
moved {
  from = google_service_account_iam_binding.allow-pubsub-to-mint-tokens
  to   = google_service_account_iam_binding.allow-pubsub-to-mint-tokens[0]
}

// The singular workqueue resources now have count = (workqueue_enabled ? 1 : 0),
// disabled when shards > 1 delegates the workqueue to hyperqueue instances.
// Existing deployments have state at the bare address; move to [0].
moved {
  from = random_string.bucket_suffix
  to   = random_string.bucket_suffix[0]
}
moved {
  from = google_storage_bucket.global-workqueue
  to   = google_storage_bucket.global-workqueue[0]
}
moved {
  from = google_storage_bucket_iam_binding.global-authorize-access
  to   = google_storage_bucket_iam_binding.global-authorize-access[0]
}
moved {
  from = random_string.receiver
  to   = random_string.receiver[0]
}
moved {
  from = google_service_account.receiver
  to   = google_service_account.receiver[0]
}
moved {
  from = module.receiver-service
  to   = module.receiver-service[0]
}
moved {
  from = random_string.dispatcher
  to   = random_string.dispatcher[0]
}
moved {
  from = google_service_account.dispatcher
  to   = google_service_account.dispatcher[0]
}
moved {
  from = random_string.cron-trigger
  to   = random_string.cron-trigger[0]
}
moved {
  from = google_service_account.cron-trigger
  to   = google_service_account.cron-trigger[0]
}
moved {
  from = random_string.reenqueue
  to   = random_string.reenqueue[0]
}
moved {
  from = google_service_account.reenqueue
  to   = google_service_account.reenqueue[0]
}
moved {
  from = google_storage_bucket_iam_member.reenqueue-bucket-access
  to   = google_storage_bucket_iam_member.reenqueue-bucket-access[0]
}
moved {
  from = module.reenqueue
  to   = module.reenqueue[0]
}
