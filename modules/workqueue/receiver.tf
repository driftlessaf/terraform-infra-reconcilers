// Compute a suffix that satisfies the regex:
// ^[a-z](?:[-a-z0-9]{4,28}[a-z0-9])$
resource "random_string" "receiver" {
  count = local.workqueue_enabled ? 1 : 0

  length  = 30 - length(local.sa_prefix)
  special = false
  upper   = false
}

// Create a dedicated GSA for the receiver service.
resource "google_service_account" "receiver" {
  count   = local.workqueue_enabled ? 1 : 0
  project = local.project_id

  account_id   = "${local.sa_prefix}${random_string.receiver[0].result}"
  display_name = "Workqueue Receiver"
  description  = "The identity as which the workqueue receiver service runs for the ${local.name} workqueue."
}

// Stand up the receiver service in each of our regions.
module "receiver-service" {
  count              = local.workqueue_enabled ? 1 : 0
  source             = "chainguard-dev/common/infra//modules/regional-go-service"
  observability_role = var.observability_role
  project_id         = local.project_id
  name               = local.receiver_service_name
  regions            = local.regions
  labels             = merge({ "service" : local.reconciler_service_name }, local.merged_labels)
  team               = local.team
  product            = local.product

  deletion_protection = local.deletion_protection

  service_account = google_service_account.receiver[0].email
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
            for k, v in local.regions : k => google_storage_bucket.global-workqueue[0].name
          }
        },
      ]
      regional-cpu-idle = lookup(local.cpu_idle, "receiver", {})
    }
  }

  ingress = local.receiver_ingress
  # A workqueue receiver is only ever invoked by authenticated principals (the
  # dispatcher, and enqueuers granted roles/run.invoker) — never by browsers
  # behind an auth-handling load balancer. Without this, regional-service grants
  # roles/run.invoker to allUsers whenever ingress != INTERNAL_ONLY, which would
  # make a receiver opened to INGRESS_TRAFFIC_ALL publicly invocable. Force
  # Cloud Run IAM auth so access stays limited to the explicit invoker grants.
  # No-op for INTERNAL_ONLY receivers (the allUsers binding is already skipped).
  require_authenticated_invocations = true

  notification_channels = local.notification_channels
  version               = "1.21.2"
}
