# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

# Plan-only guard that candidate-window-factor reaches both dispatcher modes and
# stays off unless set.

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


run "spreading_disabled_by_default" {
  command = plan

  assert {
    condition = alltrue([
      one([for e in local.long_mode_dispatcher_env : e.value if e.name == "WORKQUEUE_CANDIDATE_WINDOW_FACTOR"]) == "0",
      one([for e in local.short_mode_dispatcher_env : e.value if e.name == "WORKQUEUE_CANDIDATE_WINDOW_FACTOR"]) == "0",
    ])
    error_message = "candidate spreading must be opt-in in both dispatcher modes"
  }
}

run "window_factor_is_forwarded" {
  command = plan

  variables {
    candidate-window-factor = 48
  }

  assert {
    condition = alltrue([
      one([for e in local.long_mode_dispatcher_env : e.value if e.name == "WORKQUEUE_CANDIDATE_WINDOW_FACTOR"]) == "48",
      one([for e in local.short_mode_dispatcher_env : e.value if e.name == "WORKQUEUE_CANDIDATE_WINDOW_FACTOR"]) == "48",
    ])
    error_message = "the configured candidate window factor was not forwarded to both dispatcher modes"
  }
}

run "window_factor_above_cap_is_rejected" {
  command = plan

  variables {
    candidate-window-factor = 129
  }

  expect_failures = [var.candidate-window-factor]
}

run "fractional_window_factor_is_rejected" {
  command = plan

  variables {
    candidate-window-factor = 47.5
  }

  expect_failures = [var.candidate-window-factor]
}
