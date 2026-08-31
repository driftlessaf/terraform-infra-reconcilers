output "receiver" {
  depends_on = [module.receiver-service]
  value = {
    name = local.receiver_service_name
  }
}

output "dispatcher" {
  depends_on = [module.dispatcher-service]
  value = {
    name = local.dispatcher_service_name
  }
}

output "scheduled_wait_warning_threshold" {
  description = "The threshold after which scheduled work emits a waiting warning."
  value       = var.scheduled_wait_warning_threshold
}

output "bucket" {
  description = "The name of the GCS bucket backing the workqueue."
  value       = google_storage_bucket.global-workqueue[0].name
}
