// module.dispatcher-service now has count = (dispatcher_service_enabled ? 1 : 0).
// Existing deployments have state at the bare address; move to [0].
moved {
  from = module.dispatcher-service
  to   = module.dispatcher-service[0]
}

// The singular workqueue resources now have count = (workqueue_enabled ? 1 : 0),
// so a wrapper can disable them when a sharded (hyperqueue) workqueue replaces
// them. Existing deployments have state at the bare address; move to [0].
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
