# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

mock_provider "ko" {}
mock_provider "cosign" {}
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
  concurrent-work = 2
  reconciler-service = {
    name = "fixture-reconciler"
  }
  team                  = "fixture"
  notification_channels = []
}

run "warning_disabled_by_default" {
  command = plan

  providers = {
    ko          = ko
    cosign      = cosign
    google      = google
    google-beta = google-beta
    null        = null
    random      = random
  }

  assert {
    condition = alltrue([
      for queue in values(module.workqueue) : queue.scheduled_wait_warning_threshold == "0s"
    ])
    error_message = "the scheduled wait warning must be disabled for every shard by default"
  }
}

run "warning_threshold_is_forwarded" {
  command = plan

  providers = {
    ko          = ko
    cosign      = cosign
    google      = google
    google-beta = google-beta
    null        = null
    random      = random
  }

  variables {
    scheduled_wait_warning_threshold = "1h"
  }

  assert {
    condition = alltrue([
      for queue in values(module.workqueue) : queue.scheduled_wait_warning_threshold == "1h"
    ])
    error_message = "the configured scheduled wait warning threshold was not forwarded to every shard"
  }
}

run "multi_unit_warning_threshold_is_rejected" {
  command = plan

  providers = {
    ko          = ko
    cosign      = cosign
    google      = google
    google-beta = google-beta
    null        = null
    random      = random
  }

  variables {
    scheduled_wait_warning_threshold = "1h30m"
  }

  expect_failures = [var.scheduled_wait_warning_threshold]
}
