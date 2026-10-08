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

run "every_minute_by_default" {
  command = plan

  assert {
    condition     = local.job_cronspec["us-central1"].schedule == "* * * * *"
    error_message = "a long-mode job must keep its per-minute schedule unless one is set"
  }

  assert {
    condition     = length([for e in local.long_mode_dispatcher_env : e if e.name == "WORKQUEUE_REPORT_EVERY"]) == 0
    error_message = "a per-minute schedule must keep the dispatcher's default dead-letter report cadence"
  }
}

run "sparse_schedule_reports_every_execution" {
  command = plan

  variables {
    schedule = "*/5 * * * *"
  }

  assert {
    condition     = local.job_cronspec["us-central1"].schedule == "*/5 * * * *"
    error_message = "the configured schedule was not passed to the job's Cloud Scheduler trigger"
  }

  assert {
    condition     = one([for e in local.long_mode_dispatcher_env : e.value if e.name == "WORKQUEUE_REPORT_EVERY"]) == "1m"
    error_message = "a sparser schedule must make every idle execution report its dead-letter backlog"
  }
}

run "fifteen_minute_schedule_is_accepted" {
  command = plan

  variables {
    schedule = "*/15 * * * *"
  }

  assert {
    condition     = local.job_cronspec["us-central1"].schedule == "*/15 * * * *"
    error_message = "a valid schedule was not passed to the job's Cloud Scheduler trigger"
  }
}

run "schedule_sparser_than_fifteen_minutes_is_rejected" {
  command = plan

  variables {
    schedule = "*/16 * * * *"
  }

  expect_failures = [var.schedule]
}

run "thirty_minute_schedule_is_rejected" {
  command = plan

  variables {
    schedule = "*/30 * * * *"
  }

  expect_failures = [var.schedule]
}

run "hourly_schedule_is_rejected" {
  command = plan

  variables {
    schedule = "0 * * * *"
  }

  expect_failures = [var.schedule]
}

run "zero_step_is_rejected" {
  command = plan

  variables {
    schedule = "*/0 * * * *"
  }

  expect_failures = [var.schedule]
}

run "restricted_hours_are_rejected" {
  command = plan

  variables {
    schedule = "*/5 8 * * *"
  }

  expect_failures = [var.schedule]
}
