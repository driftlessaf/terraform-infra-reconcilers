# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

mock_provider "google" {
  mock_data "google_project" {
    defaults = {
      number = "123456789"
    }
  }
}
mock_provider "google-beta" {}
mock_provider "null" {}
mock_provider "random" {
  mock_resource "random_string" {
    override_during = plan
    defaults = {
      result = "abc123"
    }
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
  concurrent-work = 1
  reconciler-service = {
    name = "fixture-reconciler"
  }
  team                  = "fixture"
  notification_channels = []
}

run "warning_disabled_by_default" {
  command = plan

  assert {
    condition     = one([for e in local.short_mode_dispatcher_env : e.value if e.name == "WORKQUEUE_SCHEDULED_WAIT_WARNING_THRESHOLD"]) == "0s"
    error_message = "the short-mode scheduled wait warning must be opt-in"
  }
}

run "warning_threshold_is_forwarded" {
  command = plan

  variables {
    scheduled_wait_warning_threshold = "1h"
  }

  assert {
    condition     = one([for e in local.short_mode_dispatcher_env : e.value if e.name == "WORKQUEUE_SCHEDULED_WAIT_WARNING_THRESHOLD"]) == "1h"
    error_message = "the configured scheduled wait warning threshold was not forwarded to the short-mode dispatcher"
  }
}

run "overflowing_warning_threshold_is_rejected" {
  command = plan

  variables {
    scheduled_wait_warning_threshold = "9999999h"
  }

  expect_failures = [var.scheduled_wait_warning_threshold]
}

run "multi_unit_warning_threshold_is_rejected" {
  command = plan

  variables {
    scheduled_wait_warning_threshold = "1h30m"
  }

  expect_failures = [var.scheduled_wait_warning_threshold]
}
