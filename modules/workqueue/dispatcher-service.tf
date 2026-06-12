// Stand up the dispatcher service in each of our regions.
// Not used in long mode, where the dispatcher runs inside a Cloud Run Job.
module "dispatcher-service" {
  count      = local.dispatcher_service_enabled ? 1 : 0
  source     = "chainguard-dev/common/infra//modules/regional-go-service"
  project_id = local.project_id
  name       = local.dispatcher_service_name
  regions    = local.regions
  labels     = merge({ "service" : local.reconciler_service_name }, local.merged_labels)
  team       = local.team
  product    = local.product

  # Give the things in the workqueue a lot of time to process the key.
  request_timeout_seconds = 3600

  deletion_protection = local.deletion_protection

  service_account = local.dispatcher_sa_email
  containers = {
    "dispatcher" = {
      source = {
        working_dir = "${path.module}/../.."
        importpath  = "chainguard.dev/terraform-infra-reconcilers/modules/workqueue/cmd/dispatcher"
      }
      ports = [{
        name           = "h2c"
        container_port = 8080
      }]
      env = [
        { name = "WORKQUEUE_MODE", value = "gcs" },
        { name = "WORKQUEUE_CONCURRENCY", value = "${local.concurrent_work}" },
        { name = "WORKQUEUE_MAX_RETRY", value = "${local.max_retry}" },
        { name = "WORKQUEUE_BATCH_SIZE", value = tostring(local.dispatcher_batch_size) },
        { name = "WORKQUEUE_NAME", value = local.name },
      ]
      regional-env = concat([
        {
          name  = "WORKQUEUE_BUCKET"
          value = { for k, v in local.regions : k => google_storage_bucket.global-workqueue.name }
        },
        {
          name  = "WORKQUEUE_TARGET"
          value = { for k, v in module.dispatcher-calls-target : k => v.uri }
        },
        ], local.error_event_ingress != null ? [
        {
          name  = "ERROR_EVENT_INGRESS_URI"
          value = { for k, v in module.dispatcher-calls-error-broker : k => v.uri }
        },
      ] : [])
      regional-cpu-idle = lookup(local.cpu_idle, "dispatcher", {})
    }
  }

  notification_channels = local.notification_channels
  version               = "1.0.13"
}
