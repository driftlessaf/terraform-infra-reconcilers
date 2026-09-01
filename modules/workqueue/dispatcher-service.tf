locals {
  short_mode_dispatcher_env = [
    { name = "WORKQUEUE_MODE", value = "gcs" },
    { name = "WORKQUEUE_CONCURRENCY", value = tostring(local.concurrent_work) },
    { name = "WORKQUEUE_OWNER_CONCURRENCY", value = tostring(coalesce(local.regional_concurrent_work, 0)) },
    { name = "WORKQUEUE_MAX_RETRY", value = tostring(local.max_retry) },
    { name = "WORKQUEUE_BATCH_SIZE", value = tostring(local.dispatcher_batch_size) },
    { name = "WORKQUEUE_NAME", value = local.name },
    { name = "WORKQUEUE_SCHEDULED_WAIT_WARNING_THRESHOLD", value = var.scheduled_wait_warning_threshold },
  ]
}

// Stand up the dispatcher service in each of our regions.
// Not used in long mode, where the dispatcher runs inside a Cloud Run Job.
module "dispatcher-service" {
  count              = local.dispatcher_service_enabled ? 1 : 0
  source             = "chainguard-dev/common/infra//modules/regional-go-service"
  observability_role = var.observability_role
  project_id         = local.project_id
  name               = local.dispatcher_service_name
  regions            = local.regions
  labels             = merge({ "service" : local.reconciler_service_name }, local.merged_labels)
  team               = local.team
  product            = local.product

  # Give the things in the workqueue a lot of time to process the key.
  request_timeout_seconds = 3600

  deletion_protection = local.deletion_protection

  service_account = local.dispatcher_sa_email

  # Defer the dispatcher SA's observability grants to the caller when it opts in
  # (e.g. regional-go-reconciler sharing one SA across reconciler + dispatcher).
  enable_observability_iam = var.enable_observability_iam

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
      env = local.short_mode_dispatcher_env
      regional-env = concat([
        {
          name  = "WORKQUEUE_BUCKET"
          value = { for k, v in local.regions : k => google_storage_bucket.global-workqueue[0].name }
        },
        {
          name  = "WORKQUEUE_TARGET"
          value = { for k, v in module.dispatcher-calls-target : k => v.uri }
        },
        {
          # Recorded on each key this dispatcher claims, so in-progress work
          # can be attributed to a region.
          name  = "WORKQUEUE_OWNER"
          value = { for k, v in local.regions : k => k }
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

  resource_manager_tags = var.resource_manager_tags
  version               = "1.37.2"
}
