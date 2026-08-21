# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Run in CI by .github/workflows/tf-module-tests.yaml.
#
# Plan-only. Covers the gated bucket binding and the setproduct Pub/Sub parents.

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

run "resource_manager_tags_default_to_empty" {
  command = plan

  assert {
    condition     = length(google_tags_location_tag_binding.global_workqueue_bucket) == 0
    error_message = "the empty default must create no bucket binding"
  }
  assert {
    condition     = length(google_tags_tag_binding.global_object_change_topic) == 0
    error_message = "the empty default must create no topic bindings"
  }
}

# nullable = false, so an explicit null must resolve to the default rather than
# failing the for_each or the gate.
run "explicit_null_is_inert" {
  command = plan

  variables {
    resource_manager_tags = null
  }

  assert {
    condition     = length(google_tags_location_tag_binding.global_workqueue_bucket) == 0
    error_message = "an explicit null must bind nothing"
  }
}

run "tags_bind_bucket_and_topic_with_project_number" {
  command = plan

  variables {
    resource_manager_tags = { "tagKeys/123" = "tagValues/456" }
  }

  # tagBindings.create needs the permanent resource name, which uses the numeric
  # project number rather than the project ID.
  assert {
    condition     = google_tags_tag_binding.global_object_change_topic["us-central1/tagKeys/123"].parent == "//pubsub.googleapis.com/projects/123456789/topics/fixture-global-us-central1"
    error_message = "Pub/Sub topic binding must use the numeric project number in a global parent"
  }
  assert {
    condition     = length(google_tags_location_tag_binding.global_workqueue_bucket) == 1
    error_message = "a non-empty map must bind the workqueue bucket"
  }
}

run "malformed_tags_are_rejected" {
  command = plan

  variables {
    resource_manager_tags = { "tagKeys/nope" = "tagValues/nope" }
  }

  expect_failures = [var.resource_manager_tags]
}
