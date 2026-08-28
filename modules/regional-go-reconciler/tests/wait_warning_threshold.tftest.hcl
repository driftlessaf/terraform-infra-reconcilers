# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

mock_provider "ko" {}
mock_provider "cosign" {}
mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  project_id = "fixture-project"
  name       = "fixture"
  mode       = "long"
  regions = {
    "us-central1" = {
      network = "projects/fixture-project/global/networks/fixture"
      subnet  = "projects/fixture-project/regions/us-central1/subnetworks/fixture"
    }
  }
  service_account       = "fixture@fixture-project.iam.gserviceaccount.com"
  notification_channels = []
  team                  = "fixture"
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

run "warning_disabled_by_default" {
  command = plan

  assert {
    condition     = one([for e in local.long_mode_dispatcher_env : e.value if e.name == "WORKQUEUE_SCHEDULED_WAIT_WARNING_THRESHOLD"]) == "0s"
    error_message = "the scheduled wait warning must be opt-in"
  }
}

run "warning_threshold_is_forwarded" {
  command = plan

  variables {
    scheduled_wait_warning_threshold = "1h"
  }

  assert {
    condition     = one([for e in local.long_mode_dispatcher_env : e.value if e.name == "WORKQUEUE_SCHEDULED_WAIT_WARNING_THRESHOLD"]) == "1h"
    error_message = "the configured scheduled wait warning threshold was not forwarded to the long-mode dispatcher"
  }
}

run "overflowing_warning_threshold_is_rejected" {
  command = plan

  variables {
    scheduled_wait_warning_threshold = "9999999h"
  }

  expect_failures = [var.scheduled_wait_warning_threshold]
}

run "sharded_short_mode_skips_long_dispatcher_env" {
  command = plan

  variables {
    mode   = "short"
    shards = 2
  }

  assert {
    condition     = length(local.long_mode_dispatcher_env) == 0
    error_message = "short mode must not evaluate the long-mode dispatcher environment"
  }
}
