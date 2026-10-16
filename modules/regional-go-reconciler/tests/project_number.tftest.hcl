# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

# The mocked lookup number differs from the supplied one, so a leaked
# google_project lookup changes the asserted parent. tags.tf is a symlink into
# the workqueue module, so this also covers the shared file in this module.
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
  resource_manager_tags = { "tagKeys/123" = "tagValues/456" }
}

run "project_number_is_used_by_the_shared_tags" {
  command = plan

  variables {
    project_number = "987654321"
  }

  assert {
    condition     = length(data.google_project.resource_manager_tags) == 0
    error_message = "project_number must skip the google_project data source"
  }
  assert {
    condition     = startswith(google_tags_tag_binding.global_object_change_topic["us-central1/tagKeys/123"].parent, "//pubsub.googleapis.com/projects/987654321/topics/")
    error_message = "topic binding parent must use the supplied project_number"
  }
}

run "project_number_is_forwarded_to_the_sharded_workqueue" {
  command = plan

  variables {
    project_number = "987654321"
    mode           = "short"
    shards         = 2
  }

  assert {
    condition = length(module.workqueue-sharded[0].tag_binding_parents) == 2 && alltrue([
      for shard, parents in module.workqueue-sharded[0].tag_binding_parents : length(parents) > 0 && alltrue([
        for k, p in parents : startswith(p, "//pubsub.googleapis.com/projects/987654321/")
      ])
    ])
    error_message = "every shard workqueue must build its tag binding parents from the forwarded project_number"
  }
}

run "null_project_number_falls_back_to_lookup" {
  command = plan

  assert {
    condition     = startswith(google_tags_tag_binding.global_object_change_topic["us-central1/tagKeys/123"].parent, "//pubsub.googleapis.com/projects/123456789/topics/")
    error_message = "topic binding parent must use the looked-up number when project_number is null"
  }
}
