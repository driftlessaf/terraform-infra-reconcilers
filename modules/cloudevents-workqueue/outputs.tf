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

output "trigger_targets" {
  description = "For each trigger key, the broker region whose topic it subscribes to and the subscriber region it pushes to. They differ only for regions fanned in to fan_in_region."
  value = {
    for key, t in merge(local.shared_trigger_index, local.extra_trigger_index) :
    key => { region = t.region, target = t.target }
  }
}
