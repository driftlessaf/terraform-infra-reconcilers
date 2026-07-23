resource "google_monitoring_alert_policy" "dead_letter_queue" {
  count = coalesce(local.max_retry, 0) > 0 && local.enable_dead_letter_alerting && local.workqueue_enabled ? 1 : 0

  project      = local.project_id
  display_name = "Workqueue dead-lettered keys ${local.name}"
  combiner     = "OR"
  severity     = "ERROR"

  alert_strategy {
    auto_close = "3600s"
  }

  conditions {
    display_name = "Workqueue dead-letter queue ${local.name}"

    condition_threshold {
      comparison      = "COMPARISON_GT"
      threshold_value = local.dead_letter_alert_threshold
      duration        = local.dead_letter_alert_duration

      filter = <<EOT
        resource.type = "prometheus_target"
        AND metric.type = "prometheus.googleapis.com/workqueue_dead_lettered_keys/gauge"
        AND metric.label."service_name" = "${local.dispatcher_service_name}"
      EOT

      # The dead-lettered-keys gauge is a global property of the workqueue (one
      # shared bucket), but every dispatcher instance/revision publishes its own
      # copy under a distinct instance/revision label. REDUCE_NONE would evaluate
      # each of those as a separate time series and therefore a separate incident,
      # so every rollout or autoscale event closes the old series ("returned to
      # normal") and opens a fresh one — a stuck DLQ then flaps open/closed
      # indefinitely. Collapse all series for the dispatcher into one by taking the
      # max across them, grouped by service_name, so there is exactly one incident
      # per workqueue regardless of how many instances/revisions report.
      aggregations {
        alignment_period     = "60s"
        cross_series_reducer = "REDUCE_MAX"
        per_series_aligner   = "ALIGN_MAX"
        group_by_fields      = ["metric.label.service_name"]
      }

      trigger {
        count = 1
      }
    }
  }

  documentation {
    subject = "Workqueue ${local.name} has dead-lettered keys"
    content = "${local.dispatcher_service_name} has dead-lettered keys above threshold. Investigate and drain the dead-letter queue."
  }

  notification_channels = local.notification_channels
}
