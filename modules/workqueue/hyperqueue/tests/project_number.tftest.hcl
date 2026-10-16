# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0
#
# The mocked lookup number differs from the supplied one, so a shard that
# does not receive project_number reads the lookup and changes the parent.

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
  shards     = 2
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
  resource_manager_tags = { "tagKeys/123" = "tagValues/456" }
}

run "project_number_is_forwarded_to_every_shard" {
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
    project_number = "987654321"
  }

  assert {
    condition = length(output.tag_binding_parents) == 2 && alltrue([
      for shard, parents in output.tag_binding_parents : length(parents) > 0 && alltrue([
        for k, p in parents : startswith(p, "//pubsub.googleapis.com/projects/987654321/")
      ])
    ])
    error_message = "every shard workqueue must build its tag binding parents from the forwarded project_number"
  }
}

run "null_project_number_falls_back_to_lookup" {
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
      for shard, parents in output.tag_binding_parents : alltrue([
        for k, p in parents : startswith(p, "//pubsub.googleapis.com/projects/123456789/")
      ])
    ])
    error_message = "shards must use the looked-up number when project_number is null"
  }
}
