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

run "single_pass_by_default" {
  command = plan

  assert {
    condition = alltrue([
      one([for e in local.long_mode_dispatcher_env : e.value if e.name == "WORKQUEUE_CLAIM_WINDOW"]) == "0s",
      one([for e in local.long_mode_dispatcher_env : e.value if e.name == "WORKQUEUE_CLAIM_POLL"]) == "10s",
    ])
    error_message = "a long-mode job must keep its single dispatch pass unless a claim window is set"
  }
}

run "claim_window_is_forwarded" {
  command = plan

  variables {
    claim_window = "600s"
    claim_poll   = "5s"
  }

  assert {
    condition = alltrue([
      one([for e in local.long_mode_dispatcher_env : e.value if e.name == "WORKQUEUE_CLAIM_WINDOW"]) == "600s",
      one([for e in local.long_mode_dispatcher_env : e.value if e.name == "WORKQUEUE_CLAIM_POLL"]) == "5s",
    ])
    error_message = "the claim window and poll were not forwarded to the long-mode dispatcher"
  }
}

run "multi_unit_claim_window_is_rejected" {
  command = plan

  variables {
    claim_window = "10m30s"
  }

  expect_failures = [var.claim_window]
}

run "zero_claim_poll_is_rejected" {
  command = plan

  variables {
    claim_poll = "0s"
  }

  expect_failures = [var.claim_poll]
}
