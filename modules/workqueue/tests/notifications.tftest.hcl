# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Run in CI by .github/workflows/tf-module-tests.yaml.
#
# Plan-only. Every published object change is a dispatch trigger in every
# region, so these assertions fail if a notification loses its prefix or event
# filter and the dispatcher's own claims and heartbeats start waking it again.

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
    "us-east4" = {
      network = "projects/fixture-project/global/networks/fixture"
      subnet  = "projects/fixture-project/regions/us-east4/subnetworks/fixture"
    }
  }
  concurrent-work = 1
  reconciler-service = {
    name = "fixture-reconciler"
  }
  team                  = "fixture"
  notification_channels = []
}

run "queued_notification_publishes_only_claimable_changes" {
  command = plan

  assert {
    condition     = length(google_storage_notification.global-object-change-notifications) == 2
    error_message = "every region needs its own queued/ notification"
  }
  assert {
    condition = alltrue([
      for n in google_storage_notification.global-object-change-notifications :
      n.object_name_prefix == "queued/" && toset(n.event_types) == toset(["OBJECT_FINALIZE", "OBJECT_METADATA_UPDATE"])
    ])
    error_message = "the queued/ notification must publish only OBJECT_FINALIZE and OBJECT_METADATA_UPDATE under queued/"
  }
}

run "lease_notification_publishes_only_released_slots" {
  command = plan

  assert {
    condition     = length(google_storage_notification.global-lease-release-notifications) == 2
    error_message = "every region needs its own in-progress/ notification"
  }
  assert {
    condition = alltrue([
      for n in google_storage_notification.global-lease-release-notifications :
      n.object_name_prefix == "in-progress/" && toset(n.event_types) == toset(["OBJECT_DELETE"])
    ])
    error_message = "the in-progress/ notification must publish only OBJECT_DELETE under in-progress/"
  }
}
