output "receiver" {
  depends_on = [module.receiver-service]
  value = {
    name = "${var.name}-rcv"
  }
}

output "dispatcher" {
  depends_on = [module.dispatcher-service]
  value = {
    name = "${var.name}-dsp"
  }
}

output "bucket" {
  description = "The name of the GCS bucket backing the workqueue."
  value       = google_storage_bucket.global-workqueue.name
}
