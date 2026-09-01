resource "random_string" "bucket_suffix" {
  count = local.workqueue_enabled ? 1 : 0

  length  = 6 // Same length as "global"
  special = false
  upper   = false
  numeric = true
}

resource "google_storage_bucket" "global-workqueue" {
  count = local.workqueue_enabled ? 1 : 0

  name          = "${local.name}-${random_string.bucket_suffix[0].result}"
  project       = local.project_id
  location      = local.multi_regional_location
  force_destroy = true
  labels        = local.merged_labels

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
}

resource "google_storage_bucket_iam_binding" "global-authorize-access" {
  count = local.workqueue_enabled ? 1 : 0

  bucket = google_storage_bucket.global-workqueue[0].name
  role   = "roles/storage.admin"
  members = concat([
    "serviceAccount:${google_service_account.receiver[0].email}",
    "serviceAccount:${google_service_account.dispatcher[0].email}",
  ], local.additional_bucket_members)
}

// Read-only access to the bucket, for producers that need to see the queue's
// shape rather than change it.
//
// It exists because the two bindings around it are the only other way in, and
// both grant delete. A producer calling gcs.QueuedDepth needs storage.objects.list
// and nothing else; without this it would take the right to remove keys from
// queued/, in-progress/ and dead-letter/ in exchange for a count, which is a
// poor trade for backpressure.
//
// objectViewer rather than legacyBucketReader: the count lists objects under a
// prefix, which is an object permission, and bucket-level metadata is not part
// of the question.
resource "google_storage_bucket_iam_member" "queue-readers" {
  for_each = toset(local.workqueue_enabled ? local.queue_reader_members : [])

  bucket = google_storage_bucket.global-workqueue[0].name
  role   = "roles/storage.objectViewer"
  member = each.value
}

resource "google_storage_bucket_iam_member" "dlq-operators" {
  for_each = toset(local.workqueue_enabled ? local.dlq_operator_members : [])

  bucket = google_storage_bucket.global-workqueue[0].name
  role   = "roles/storage.objectAdmin"
  member = each.value
}

resource "google_pubsub_topic" "global-object-change-notifications" {
  for_each = local.workqueue_enabled ? local.regions : {}

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
  for_each = local.workqueue_enabled ? local.regions : {}

  topic   = google_pubsub_topic.global-object-change-notifications[each.key].id
  role    = "roles/pubsub.publisher"
  members = ["serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"]
}

resource "google_storage_notification" "global-object-change-notifications" {
  for_each = local.workqueue_enabled ? local.regions : {}

  // We depend on the IAM binding granting the GCS service account pubsub.publisher
  // on the topic. GCP IAM is eventually consistent, and the GCS notification API
  // validates this permission at creation time.
  depends_on = [
    google_pubsub_topic_iam_binding.global-gcs-publishes-to-topic,
  ]

  bucket         = google_storage_bucket.global-workqueue[0].name
  payload_format = "JSON_API_V1"
  topic          = google_pubsub_topic.global-object-change-notifications[each.key].id
}
