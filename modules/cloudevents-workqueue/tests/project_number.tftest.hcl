# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

# Plan-only. The mocked lookup number differs from the supplied one, so a
# trigger that does not receive project_number reads the lookup and changes
# the asserted parent.
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
  name       = "fixture-pr"
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
  broker = {
    "us-central1" = "shared-us-central1"
    "us-east4"    = "shared-us-east4"
  }
  filters = [
    { subject = "org/repo", type = "dev.chainguard.github.pull_request" },
    { subject = "org/other" },
  ]
  filter_prefix         = { headbranch = "fixture/" }
  extension_key         = "pullrequesturl"
  workqueue             = { name = "fixture-rcv" }
  notification_channels = []
  team                  = "fixture"
  resource_manager_tags = { "tagKeys/123" = "tagValues/456" }
}

run "project_number_is_forwarded_to_every_trigger" {
  command = plan

  variables {
    project_number = "987654321"
  }

  assert {
    condition = length(module.trigger) == 4 && alltrue([
      for k, t in module.trigger : length(t.tag_binding_parents) == 3 && alltrue([
        for name, p in t.tag_binding_parents : startswith(p, "//pubsub.googleapis.com/projects/987654321/")
      ])
    ])
    error_message = "every trigger must build its tag binding parents from the forwarded project_number"
  }
}

run "null_project_number_falls_back_to_lookup" {
  command = plan

  assert {
    condition = alltrue([
      for k, t in module.trigger : alltrue([
        for name, p in t.tag_binding_parents : startswith(p, "//pubsub.googleapis.com/projects/123456789/")
      ])
    ])
    error_message = "triggers must use the looked-up number when project_number is null"
  }
}
