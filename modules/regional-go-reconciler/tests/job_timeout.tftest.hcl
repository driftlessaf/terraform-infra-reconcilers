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

run "job_timeout_is_forwarded_by_default" {
  command = plan

  assert {
    condition     = one([for e in local.long_mode_dispatcher_env : e.value if e.name == "WORKQUEUE_JOB_TIMEOUT"]) == "3600s"
    error_message = "the long-mode dispatcher must know the job timeout so a reconcile that runs out the clock counts as a failed attempt"
  }
}

run "custom_job_timeout_is_forwarded" {
  command = plan

  variables {
    job_timeout = "7200s"
  }

  assert {
    condition     = one([for e in local.long_mode_dispatcher_env : e.value if e.name == "WORKQUEUE_JOB_TIMEOUT"]) == "7200s"
    error_message = "a custom job_timeout was not forwarded to the long-mode dispatcher"
  }
}
