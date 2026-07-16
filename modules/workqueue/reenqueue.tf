# Dead-letter reenqueue Cloud Run Job
# This job allows manual reenqueuing of dead-lettered workqueue items.

// Compute a suffix that satisfies the regex:
// ^[a-z](?:[-a-z0-9]{4,28}[a-z0-9])$
resource "random_string" "reenqueue" {
  length  = 30 - length(local.sa_prefix)
  special = false
  upper   = false
}

// Create a dedicated GSA for the reenqueue job.
resource "google_service_account" "reenqueue" {
  project = local.project_id

  account_id   = "${local.sa_prefix}${random_string.reenqueue.result}"
  display_name = "Workqueue Reenqueue Job"
  description  = "The identity as which the workqueue reenqueue job runs for the ${local.name} workqueue."
}

// Authorize the reenqueue service account to read/write the bucket (for Enumerate and Queue)
resource "google_storage_bucket_iam_member" "reenqueue-bucket-access" {
  bucket = google_storage_bucket.global-workqueue.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.reenqueue.email}"
}

// The reenqueue cron job (paused by default, for manual invocation)
module "reenqueue" {
  source = "chainguard-dev/common/infra//modules/cron"

  project_id         = local.project_id
  observability_role = var.observability_role
  name               = local.reenqueue_job_name
  region             = local.reenqueue_region
  service_account    = google_service_account.reenqueue.email

  importpath  = "chainguard.dev/terraform-infra-reconcilers/modules/workqueue/cmd/reenqueue"
  working_dir = "${path.module}/../.."

  # Paused by default - this job is meant to be manually triggered
  paused   = true
  schedule = "0 0 * * *" # Placeholder, never runs when paused

  # Additional IAM members allowed to execute the job (beyond the job's own
  # invoker SA), so operators can manually requeue dead-lettered items.
  invokers = local.reenqueue_invokers

  env = {
    "WORKQUEUE_MODE"        = "gcs"
    "WORKQUEUE_BUCKET"      = google_storage_bucket.global-workqueue.name
    "WORKQUEUE_CONCURRENCY" = local.concurrent_work
  }

  # VPC access using the reenqueue region's network configuration
  vpc_access = {
    network_interfaces = [{
      network    = local.regions[local.reenqueue_region].network
      subnetwork = local.regions[local.reenqueue_region].subnet
    }]
    egress = "ALL_TRAFFIC" // This should not egress
  }

  team                  = local.team
  product               = local.product
  notification_channels = local.notification_channels
  deletion_protection   = local.deletion_protection
  version               = "1.19.2"
}
