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
  target  = module.reenqueue
  outputs = {}
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
  assert {
    condition     = length(google_service_account.dispatcher) == 1
    error_message = "the dispatcher account stays until its bucket grant can be removed without shifting the others"
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
