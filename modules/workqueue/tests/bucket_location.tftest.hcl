# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Run in CI by .chainguard/ci/tf-module-tests.yaml.
#
# Plan-only. Covers the optional single-region bucket location.

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

run "default_is_multi_region_us" {
  command = plan

  assert {
    condition     = google_storage_bucket.global-workqueue[0].location == "US"
    error_message = "the default bucket location must be US"
  }
}

run "null_bucket_location_follows_multi_regional_location" {
  command = plan

  variables {
    multi_regional_location = "EU"
  }

  assert {
    condition     = google_storage_bucket.global-workqueue[0].location == "EU"
    error_message = "a null bucket_location must use multi_regional_location"
  }
}

run "bucket_location_overrides_to_region" {
  command = plan

  variables {
    bucket_location = "us-central1"
  }

  assert {
    condition     = google_storage_bucket.global-workqueue[0].location == "us-central1"
    error_message = "bucket_location must set the bucket location"
  }
}

run "bucket_location_overrides_to_multi_region" {
  command = plan

  variables {
    bucket_location = "EU"
  }

  assert {
    condition     = google_storage_bucket.global-workqueue[0].location == "EU"
    error_message = "bucket_location must accept a multi-region"
  }
}

run "malformed_bucket_location_is_rejected" {
  command = plan

  variables {
    bucket_location = "nowhere"
  }

  expect_failures = [var.bucket_location]
}
