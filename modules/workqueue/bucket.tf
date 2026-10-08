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

locals {
  // Splats rather than [0] indexes, because regional-go-reconciler sets
  // workqueue_enabled false whenever it is sharded, and this expression is
  // evaluated either way. A [0] index would have to survive the unchosen
  // branch of the count below to be safe; [*] yields an empty list when
  // the account is not created and needs no such guarantee.
  queue_writer_members = concat(
    [for sa in concat(
      google_service_account.receiver[*].email,
      google_service_account.dispatcher[*].email,
    ) : "serviceAccount:${sa}"],
    local.additional_bucket_members,
  )
}

// Read-write access to the queue's objects, for the identities that move work
// through it.
//
// Additive members rather than a binding on the role, and that is the
// load-bearing choice rather than a style one. A
// google_storage_bucket_iam_binding owns the complete member list for its
// role, so whichever role it claims, it evicts anyone granted that role from
// outside this module and then fights them on every subsequent plan. There is
// no safe role to claim: dlq-operators below grants objectAdmin, and consumer
// stages grant objectUser directly on these queue buckets -- production CVE
// remediation operators among them, through
// remediation_operator_queue_buckets. A module exported for outside use cannot
// see such grants at all, so it must not assume they are absent.
//
// objectUser is the role, because every operation the queue performs is on an
// object: the receiver creates a key and reads its attributes, and the
// dispatcher lists, reads, updates and deletes them as work moves between
// queued/, in-progress/ and dead-letter/. Nothing reads the bucket's own
// metadata and nothing creates or destroys a bucket -- Terraform owns that.
// Against storage.admin it withholds storage.buckets.setIamPolicy and bucket
// delete, so a compromised receiver or dispatcher can no longer rewrite its
// own access or discard the queue; against objectAdmin it also withholds
// object-level IAM control, which the queue never uses.
//
// The members are fewer identities than they look. In a standalone workqueue
// the receiver and dispatcher have dedicated accounts and
// additional_bucket_members is empty. Where the dispatcher is inlined as a
// sidecar -- regional-go-reconciler -- it runs as the reconciler service's own
// account, and that account is what appears in additional_bucket_members. So
// the extra member is the dispatcher wearing the service's identity, with the
// same object-scoped needs, not a third party with unexamined ones.
resource "google_storage_bucket_iam_member" "queue-writers" {
  // count rather than for_each, and that is forced rather than chosen. A
  // service account's email is not known until apply, so a for_each keyed on
  // these members leaves Terraform unable to name the instances it would
  // create, and the plan fails outright on any queue whose accounts do not yet
  // exist. The list's length is known even when its contents are not, so count
  // plans cleanly. The cost is positional addresses: reordering
  // additional_bucket_members re-keys the grants after it.
  count = local.workqueue_enabled ? length(local.queue_writer_members) : 0

  bucket = google_storage_bucket.global-workqueue[0].name
  role   = "roles/storage.objectUser"
  member = local.queue_writer_members[count.index]
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

// Where the dispatcher is event-driven, each notification wakes it in its
// region, so only object changes that can let a pass launch work are
// published. The two notifications below cover the two ways that happens:
//
//   - a key becomes claimable: it is written or requeued under queued/
//     (OBJECT_FINALIZE), or a duplicate enqueue raises its priority or pulls
//     its not-before earlier (OBJECT_METADATA_UPDATE);
//   - a worker slot frees up: a lease under in-progress/ is completed,
//     requeued or dead-lettered (OBJECT_DELETE).
//
// Everything else is the dispatcher's own bookkeeping: the in-progress copy
// and queued delete of every claim, lease heartbeats, and dead-letter writes.
// A not-before passing or a lease expiring changes no object at all; the
// per-minute cron covers those, and any trigger the dispatch rate limit sheds.
// A key whose enqueue trigger was shed therefore waits for the next enqueue,
// freed slot, or cron pass.
//
// Changing the filter replaces the queued/ notification. create_before_destroy
// and the dependency on the in-progress/ notification create both filtered
// notifications before the unfiltered one is removed. Cloud Storage can take
// up to 30 seconds to start delivering a new notification, so a change in
// that window may go unpublished and wait for the cron pass, as a shed
// trigger does. The overlap otherwise only sends duplicate triggers.
resource "google_storage_notification" "global-object-change-notifications" {
  for_each = local.workqueue_enabled ? local.regions : {}

  // We depend on the IAM binding granting the GCS service account pubsub.publisher
  // on the topic. GCP IAM is eventually consistent, and the GCS notification API
  // validates this permission at creation time.
  depends_on = [
    google_pubsub_topic_iam_binding.global-gcs-publishes-to-topic,
    google_storage_notification.global-lease-release-notifications,
  ]

  bucket             = google_storage_bucket.global-workqueue[0].name
  payload_format     = "JSON_API_V1"
  topic              = google_pubsub_topic.global-object-change-notifications[each.key].id
  object_name_prefix = "queued/"
  event_types        = ["OBJECT_FINALIZE", "OBJECT_METADATA_UPDATE"]

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_storage_notification" "global-lease-release-notifications" {
  for_each = local.workqueue_enabled ? local.regions : {}

  depends_on = [
    google_pubsub_topic_iam_binding.global-gcs-publishes-to-topic,
  ]

  bucket             = google_storage_bucket.global-workqueue[0].name
  payload_format     = "JSON_API_V1"
  topic              = google_pubsub_topic.global-object-change-notifications[each.key].id
  object_name_prefix = "in-progress/"
  event_types        = ["OBJECT_DELETE"]
}
