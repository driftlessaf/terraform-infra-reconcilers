locals {
  long_mode_dispatcher_env = var.mode == "long" ? [
    { name = "WORKQUEUE_MODE", value = "gcs" },
    { name = "WORKQUEUE_CONCURRENCY", value = tostring(local.concurrent_work) },
    { name = "WORKQUEUE_OWNER_CONCURRENCY", value = tostring(coalesce(local.regional_concurrent_work, 0)) },
    { name = "WORKQUEUE_MAX_RETRY", value = tostring(local.max_retry) },
    { name = "WORKQUEUE_BATCH_SIZE", value = tostring(local.dispatcher_batch_size) },
    { name = "WORKQUEUE_NAME", value = local.name },
    { name = "WORKQUEUE_TARGET", value = "http://localhost:8081" },
    { name = "WORKQUEUE_BUCKET", value = google_storage_bucket.global-workqueue[0].name },
    { name = "WORKQUEUE_SCHEDULED_WAIT_WARNING_THRESHOLD", value = var.scheduled_wait_warning_threshold },
    { name = "METRICS_PORT", value = "2113" },
  ] : []
}

// Long-mode reconciler: a Cloud Run Job that fires once per cron tick.
// The dispatcher-job container performs a single dispatch iteration and exits;
// user reconciler containers run as sidecars on localhost:8081.

module "reconciler-job" {
  count              = var.mode == "long" ? 1 : 0
  source             = "chainguard-dev/common/infra//modules/regional-go-cron"
  observability_role = var.observability_role

  project_id = var.project_id
  // Single source of truth for the job name: local.reconciler_service_name is
  // "${var.name}-rec" in long mode, and the dead-letter alert filters the
  // workqueue gauges on exactly this string (the CLOUD_RUN_JOB-derived
  // service_name label). Referencing the local keeps the job name and the
  // alert filter from drifting apart — a rename here must move the alert too.
  name            = local.reconciler_service_name
  service_account = var.service_account
  team            = var.team
  product         = var.product
  egress          = var.egress

  # Long-mode reconciler also runs as the shared var.service_account; defer its
  # observability grants to the caller when it opts in, same as the short-mode
  # reconciler and dispatcher services.
  enable_observability_iam = var.enable_observability_iam

  regions = var.regions

  regional-cronspec = { for k in keys(var.regions) : k => {
    schedule = "* * * * *"
  } }

  containers = merge(
    // Dispatcher-job as the entry-point container.
    {
      "dispatcher" = {
        source = {
          working_dir = "${path.module}/../.."
          importpath  = "chainguard.dev/terraform-infra-reconcilers/modules/workqueue/cmd/dispatcher-job"
        }
        resources = { limits = { cpu = "1", memory = "512Mi" } }
        env       = local.long_mode_dispatcher_env
        regional-env = concat([
          {
            # Recorded on each key this dispatcher claims, so in-progress
            # work can be attributed to a region.
            name  = "WORKQUEUE_OWNER"
            value = { for k in keys(var.regions) : k => k }
          },
          ], local.error_event_ingress != null ? [{
            name  = "ERROR_EVENT_INGRESS_URI"
            value = { for k, v in module.dispatcher-calls-error-broker : k => v.uri }
        }] : [])
      }
    },
    // Reconciler containers with PORT injected so they listen on the sidecar port.
    // Field-wise copy required: var.containers uses the regional-go-service schema
    // with typed startup_probe/liveness_probe objects that are incompatible with
    // regional-go-cron's optional(any). Both are nulled out — Cloud Run Jobs don't
    // support probes. cpu_idle and startup_cpu_boost are silently ignored by jobs.
    { for k, v in local.containers_plus_trace_env : k => {
      source            = v.source
      command           = v.command
      args              = v.args
      ports             = v.ports
      resources         = v.resources
      env               = concat(v.env, [{ name = "PORT", value = "8081" }])
      regional-env      = v.regional-env
      regional-cpu-idle = v.regional-cpu-idle
      volume_mounts     = v.volume_mounts
      startup_probe     = null
      liveness_probe    = null
    } },
  )

  timeout               = var.job_timeout
  max_retries           = 0
  deletion_protection   = var.deletion_protection
  notification_channels = var.notification_channels
  labels                = merge({ "service" : local.reconciler_service_name }, var.labels)

  resource_manager_tags = var.resource_manager_tags
  version               = "1.39.4"
}
