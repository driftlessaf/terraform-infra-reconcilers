# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

# Plan-only guard on the dead-letter alert's service_name filter.
#
# The workqueue gauges (workqueue_dead_lettered_keys among them) are labeled
# with the identity of the Cloud Run resource hosting the dispatcher. In short
# mode that is the standalone dispatcher service ("<name>-wq-dsp"); in long
# mode the dispatcher runs inside the "<name>-rec" Cloud Run Job and the label
# comes from the CLOUD_RUN_JOB fallback in go-driftlessaf's workqueue metrics.
# An alert filter pinned to the dispatcher service name matches nothing in
# long mode — the alert exists but can never fire. These runs pin the rendered
# filter to the label each mode actually emits.
#
# Child module calls are replaced with override_module so the plan stays fully
# offline: no credentials, no state. The providers are mocked as well —
# override_module skips the child modules' resources, but the providers they
# require are still configured, and the real ones would try to load
# application default credentials.

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

run "short_mode_alert_filters_on_dispatcher_service" {
  command = plan

  variables {
    mode = "short"
  }

  assert {
    condition     = strcontains(google_monitoring_alert_policy.dead_letter_queue[0].conditions[0].condition_threshold[0].filter, "metric.label.\"service_name\" = \"fixture-wq-dsp\"")
    error_message = "short mode must filter the dead-letter alert on the standalone dispatcher service's name (fixture-wq-dsp), the label the workqueue gauges carry when the dispatcher runs as its own service"
  }
}

run "long_mode_alert_filters_on_reconciler_job" {
  command = plan

  variables {
    mode = "long"
  }

  assert {
    condition     = strcontains(google_monitoring_alert_policy.dead_letter_queue[0].conditions[0].condition_threshold[0].filter, "metric.label.\"service_name\" = \"fixture-rec\"")
    error_message = "long mode must filter the dead-letter alert on the reconciler Job's name (fixture-rec), the CLOUD_RUN_JOB-derived label the gauges carry when the dispatcher runs inside the Job — filtering on the dispatcher service name matches nothing there"
  }

  assert {
    condition     = !strcontains(google_monitoring_alert_policy.dead_letter_queue[0].conditions[0].condition_threshold[0].filter, "fixture-wq-dsp")
    error_message = "long mode must not filter on the standalone dispatcher service's name — that service is not created in long mode, so the alert would never match"
  }
}
