resource "random_string" "bucket_suffix" {
  length  = 6 // Same length as "global"
  special = false
  upper   = false
  numeric = true
}

resource "google_storage_bucket" "global-workqueue" {
  name          = "${local.name}-${random_string.bucket_suffix.result}"
  project       = local.project_id
  location      = local.multi_regional_location
  force_destroy = true
  labels        = local.merged_labels

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
}

resource "google_storage_bucket_iam_binding" "global-authorize-access" {
  bucket = google_storage_bucket.global-workqueue.name
  role   = "roles/storage.admin"
  members = concat([
    "serviceAccount:${google_service_account.receiver.email}",
    "serviceAccount:${google_service_account.dispatcher.email}",
  ], local.additional_bucket_members)
}

resource "google_pubsub_topic" "global-object-change-notifications" {
  for_each = local.regions

  name   = "${local.name}-global-${each.key}"
  labels = local.merged_labels

  message_storage_policy {
    allowed_persistence_regions = [each.key]
  }
}

data "google_storage_project_service_account" "gcs_account" {
  project = local.project_id
}

resource "google_pubsub_topic_iam_binding" "global-gcs-publishes-to-topic" {
  for_each = local.regions

  topic   = google_pubsub_topic.global-object-change-notifications[each.key].id
  role    = "roles/pubsub.publisher"
  members = ["serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"]
}

resource "google_storage_notification" "global-object-change-notifications" {
  for_each = local.regions

  // We depend on the IAM binding granting the GCS service account pubsub.publisher
  // on the topic. GCP IAM is eventually consistent, and the GCS notification API
  // validates this permission at creation time.
  depends_on = [
    google_pubsub_topic_iam_binding.global-gcs-publishes-to-topic,
  ]

  bucket         = google_storage_bucket.global-workqueue.name
  payload_format = "JSON_API_V1"
  topic          = google_pubsub_topic.global-object-change-notifications[each.key].id
}
