locals {
  // dead_letter_error_log_filter finds the failures behind the dead-lettered
  // keys. The reconciler is a Cloud Run Service in short mode and a Job in long
  // mode, and in short mode the dispatcher that parked the key is a third
  // resource, so match every candidate name against both resource labels.
  dead_letter_error_log_filter = <<-EOT
    (resource.labels.service_name="${local.reconciler_service_name}"
     OR resource.labels.job_name="${local.reconciler_service_name}"
     OR resource.labels.service_name="${local.dead_letter_alert_service_name}"
     OR resource.labels.job_name="${local.dead_letter_alert_service_name}")
    severity>=ERROR
  EOT
}

resource "google_monitoring_alert_policy" "dead_letter_queue" {
  count = coalesce(local.max_retry, 0) > 0 && local.enable_dead_letter_alerting && local.workqueue_enabled ? 1 : 0

  project      = local.project_id
  display_name = "Workqueue dead-lettered keys ${local.name}"
  combiner     = "OR"
  severity     = "ERROR"

  # auto_close is the all-clear for the long-mode dispatcher, which publishes
  # the gauge only while it has a backlog to report, and then only every
  # reportEvery (see dispatcher-job's scrapeSignal): a drained queue goes
  # silent, and this is what closes the incident. Measured in prod, the incident
  # closes 61 minutes after the last sample — the timer runs from that sample,
  # with none of the grace the missing-data docs suggest. So this must stay
  # comfortably above dispatcher-job's reportEvery, or a healthy queue with a
  # standing backlog will flap.
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
        AND metric.label."service_name" = "${local.dead_letter_alert_service_name}"
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

    content = <<-EOT
      The `${local.name}` workqueue is holding more than ${local.dead_letter_alert_threshold} dead-lettered key(s), reported by `${local.dead_letter_alert_service_name}`.

      A key is dead-lettered after `max-retry` failed reconciliations, or immediately when the reconciler returns a `DeadLetterError`. It is then parked under the `dead-letter/` prefix of the workqueue bucket and is never retried on its own, so whatever that key represents has stopped being reconciled until someone acts.

      This alert reports a level, not an event. It stays open while the backlog stands and closes on its own an hour after the last report once the keys are gone, so it may be telling you that something broke a while ago and is still broken rather than that something just broke.

      ## Troubleshooting

      1. **See what is stuck.** List the `dead-letter/` prefix of the workqueue bucket (link below). The object name is the key; its `failed-time` metadata records when it was parked.
      2. **Find out why.** Open the reconciler error logs (link below) and search for that key. The last failure before it was parked is the one that matters.
      3. **Decide whether the failure was transient.** A capacity blip, an upstream 5xx, or a dependency that has since been fixed will succeed on a retry. Execute the `${local.reenqueue_job_name}` job (link below) to requeue every dead-lettered key with a fresh attempt counter: keys that succeed clean themselves up, and anything genuinely broken dead-letters again and re-fires this alert.
      4. **Otherwise fix the reconciler, then reenqueue.** A key that comes back after a reenqueue is a real bug or a permanently-invalid key. Check the reconciler's error classification before blaming the key — treating a transient failure as permanent parks keys that a rerun would have cleared.
      5. **If the alert flaps** — closing and reopening on a count that never changed — do not shorten `auto_close`. In long mode the gauge is published only while a dispatch job is alive and only when there is a backlog to report, and the silence between those reports is what closes the incident; see the comment on `alert_strategy` in this module's `alerts.tf`.
    EOT

    links {
      display_name = "Dead-lettered keys in GCS"
      url          = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.global-workqueue[0].name}/dead-letter?project=${local.project_id}"
    }

    links {
      display_name = "Reconciler error logs"
      url          = "https://console.cloud.google.com/logs/query;query=${urlencode(local.dead_letter_error_log_filter)}?project=${local.project_id}"
    }

    links {
      display_name = "Reenqueue job"
      url          = "https://console.cloud.google.com/run/jobs/details/${local.reenqueue_region}/${local.reenqueue_job_name}/executions?project=${local.project_id}"
    }
  }

  notification_channels = local.notification_channels
}
