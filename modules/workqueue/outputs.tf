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

output "tag_binding_parents" {
  description = "The parent of every Pub/Sub tag binding, keyed by binding, region and tag key."
  value = merge(
    { for k, b in google_tags_tag_binding.global_object_change_topic : "topic/${k}" => b.parent },
    { for k, b in google_tags_tag_binding.global_subscription : "subscription/${k}" => b.parent },
  )
}

output "bucket" {
  description = "The name of the GCS bucket backing the workqueue."
  value       = google_storage_bucket.global-workqueue[0].name
}
