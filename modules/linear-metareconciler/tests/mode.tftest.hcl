# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

# Plan-only tests through the real child modules with mocked providers.
mock_provider "ko" {}
mock_provider "cosign" {}
mock_provider "google" {
  mock_data "google_storage_project_service_account" {
    defaults = { email_address = "fixture-gcs@fixture-project.iam.gserviceaccount.com" }
  }
}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  project_id = "fixture-project"
  name       = "fixture"
  regions = {
    "us-central1" = {
      network = "projects/fixture-project/global/networks/fixture"
      subnet  = "projects/fixture-project/regions/us-central1/subnetworks/fixture"
    }
  }
  primary-region  = "us-central1"
  service_account = "fixture@fixture-project.iam.gserviceaccount.com"
  broker          = { "us-central1" = "fixture-broker" }
  team            = "fixture"
  product         = "fixture"
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

run "short_by_default" {
  command = plan

  assert {
    condition     = var.mode == "short"
    error_message = "long mode must be opt-in"
  }
}

# The reconciler service exists only in short mode, so an empty URI map is the
# evidence the mode reached the reconciler module.
run "long_mode_is_forwarded" {
  command = plan

  variables {
    mode         = "long"
    job_timeout  = "7200s"
    claim_window = "600s"
    claim_poll   = "5s"
  }

  assert {
    condition     = length(module.reconciler.reconciler-uris) == 0
    error_message = "long mode did not reach the reconciler module: a reconciler service is still planned"
  }
}

run "unknown_mode_is_rejected" {
  command = plan

  variables {
    mode = "medium"
  }

  expect_failures = [var.mode]
}
