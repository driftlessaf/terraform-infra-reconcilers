# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

# Plan-only guard on what long mode builds around the queue. The bucket's
# change topics and notifications exist to wake the dispatcher through its
# change-trigger subscription, and the cron-trigger account exists to invoke it
# on a schedule. Long mode dispatches from a Cloud Run Job on a cron and has
# neither trigger, so it must not build them. Short mode keeps them.
#
# Same offline setup as dead_letter_alert.tftest.hcl.

mock_provider "ko" {}
mock_provider "cosign" {}
mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

override_module {
  target = module.reconciler
  outputs = {
    names     = { "us-central1" = "fixture-rec" }
    locations = {}
    uris      = {}
  }
}

override_module {
  target  = module.reconciler-job
  outputs = {}
}

override_module {
  target  = module.dispatcher-service
  outputs = {}
}

override_module {
  target = module.dispatcher-calls-target
  outputs = {
    uri = "https://fixture-rec.example.com"
  }
}

override_module {
  target = module.dispatcher-calls-error-broker
  outputs = {
    uri = "https://fixture-broker.example.com"
  }
}

override_module {
  target = module.cron-trigger-calls-dispatcher
  outputs = {
    uri = "https://fixture-dsp.example.com"
  }
}

override_module {
  target = module.change-trigger-calls-dispatcher
  outputs = {
    uri = "https://fixture-dsp.example.com"
  }
}

override_module {
  target  = module.receiver-service
  outputs = {}
}

override_module {
  target = module.reenqueue
  outputs = {
    name = "fixture-wq-req-cron"
  }
}

override_module {
  target = module.reconciler-publishes-traces
  outputs = {
    uri = "https://fixture-trace.example.com"
  }
}

override_module {
  target = module.workqueue-sharded
  outputs = {
    receiver = {}
  }
}

variables {
  project_id = "fixture-project"
  name       = "fixture"
  regions = {
    "us-central1" = {
      network = "projects/fixture-project/global/networks/fixture"
      subnet  = "projects/fixture-project/regions/us-central1/subnetworks/fixture"
    }
  }
  service_account       = "fixture@fixture-project.iam.gserviceaccount.com"
  team                  = "fixture"
  notification_channels = []
  max-retry             = 5
  containers = {
    "main" = {
      source = {
        working_dir = "."
        importpath  = "example.com/fixture/cmd/app"
      }
      ports = [{ container_port = 8080 }]
    }
  }
}

run "long_mode_builds_no_trigger_plumbing" {
  command = plan

  variables {
    mode = "long"
  }

  assert {
    condition = (
      length(google_pubsub_topic.global-object-change-notifications) == 0 &&
      length(google_pubsub_topic_iam_binding.global-gcs-publishes-to-topic) == 0 &&
      length(google_storage_notification.global-object-change-notifications) == 0 &&
      length(google_storage_notification.global-lease-release-notifications) == 0
    )
    error_message = "long mode has no change trigger, so it must not publish bucket changes"
  }
  assert {
    condition     = length(google_service_account.cron-trigger) == 0
    error_message = "long mode has no dispatcher cron, so it needs no cron-trigger account"
  }
}

run "short_mode_keeps_trigger_plumbing" {
  command = plan

  assert {
    condition = (
      length(google_pubsub_topic.global-object-change-notifications) == 1 &&
      length(google_storage_notification.global-object-change-notifications) == 1 &&
      length(google_storage_notification.global-lease-release-notifications) == 1
    )
    error_message = "short mode's change trigger needs the bucket's change notifications"
  }
  assert {
    condition     = length(google_service_account.cron-trigger) == 1
    error_message = "short mode's dispatcher cron needs its cron-trigger account"
  }
}

run "pause_stops_short_mode_dispatch" {
  command = plan

  variables {
    mode   = "short"
    paused = true
  }

  assert {
    condition = (
      length(google_cloud_scheduler_job.cron) > 0 &&
      alltrue([for job in google_cloud_scheduler_job.cron : job.paused]) &&
      length(google_pubsub_subscription.global-this) == 0 &&
      local.reenqueue_paused
    )
    error_message = "Pause must stop both scheduled and object-change dispatch without reenqueueing dead letters."
  }
}

run "pause_stops_long_mode_schedule" {
  command = plan

  variables {
    mode   = "long"
    paused = true
  }

  assert {
    condition     = alltrue([for spec in values(local.job_cronspec) : spec.paused]) && local.reenqueue_paused
    error_message = "Long-mode cron specifications and dead-letter reenqueue must remain paused."
  }
}

run "default_preserves_dispatcher_pause_management" {
  command = plan

  variables {
    mode = "short"
  }

  assert {
    condition     = local.dispatcher_paused == null
    error_message = "Default callers must preserve manually paused dispatcher schedules."
  }
}

run "explicit_resume_restores_dispatch" {
  command = plan

  variables {
    mode               = "short"
    paused             = false
    reenqueue_schedule = "*/5 * * * *"
  }

  assert {
    condition = (
      alltrue([for job in google_cloud_scheduler_job.cron : job.paused == false]) &&
      length(google_pubsub_subscription.global-this) > 0 &&
      !local.reenqueue_paused
    )
    error_message = "Explicit resume must restore cron and object-change dispatch and configured reenqueue."
  }
}
