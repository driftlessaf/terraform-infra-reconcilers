output "subscriber" {
  value = {
    uris            = module.subscriber.uris
    names           = module.subscriber.names
    locations       = module.subscriber.locations
    service_account = google_service_account.subscriber.email
  }
}

output "subscriber_service_account" {
  description = "Subscriber service account for read grants on caller-owned state."
  value       = google_service_account.subscriber.email
}
