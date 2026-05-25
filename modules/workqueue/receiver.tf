// Compute a suffix that satisfies the regex:
// ^[a-z](?:[-a-z0-9]{4,28}[a-z0-9])$
resource "random_string" "receiver" {
  length  = 30 - length(local.sa_prefix)
  special = false
  upper   = false
}

// Create a dedicated GSA for the receiver service.
resource "google_service_account" "receiver" {
  project = local.project_id

  account_id   = "${local.sa_prefix}${random_string.receiver.result}"
  display_name = "Workqueue Receiver"
  description  = "The identity as which the workqueue receiver service runs for the ${local.name} workqueue."
}

// Stand up the receiver service in each of our regions.
module "receiver-service" {
  source     = "chainguard-dev/common/infra//modules/regional-go-service"
  project_id = local.project_id
  name       = local.receiver_service_name
  regions    = local.regions
  labels     = merge({ "service" : "workqueue-receiver" }, local.merged_labels)
  team       = local.team
  product    = local.product

  deletion_protection = local.deletion_protection

  service_account = google_service_account.receiver.email
  containers = {
    "receiver" = {
      source = {
        working_dir = "${path.module}/../.."
        importpath  = "chainguard.dev/terraform-infra-reconcilers/modules/workqueue/cmd/receiver"
      }
      resources = {
        limits = {
          memory = "4Gi"
          cpu    = "1000m"
        }
      }
      ports = [{ name = "h2c", container_port = 8080 }]
      env = [
        {
          name  = "WORKQUEUE_MODE"
          value = "gcs"
        },
        {
          # The receiver doesn't use this, but the workqueue constructor wants it.
          name  = "WORKQUEUE_CONCURRENCY"
          value = "${local.concurrent_work}"
        },
      ]
      regional-env = [
        {
          name = "WORKQUEUE_BUCKET"
          value = {
            for k, v in local.regions : k => google_storage_bucket.global-workqueue.name
          }
        },
      ]
      regional-cpu-idle = lookup(local.cpu_idle, "receiver", {})
    }
  }

  ingress               = local.receiver_ingress
  notification_channels = local.notification_channels
  version               = "1.0.10"
}
