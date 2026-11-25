# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

# Plan-only tests through the real child modules with mocked providers.
mock_provider "ko" {}
mock_provider "cosign" {}
mock_provider "google" {
  mock_data "google_storage_project_service_account" {
    defaults = { email_address = "fixture-gcs@fixture-project.iam.gserviceaccount.com" }
  }
}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  project_id = "fixture-project"
  name       = "fixture"
  regions = {
    "us-central1" = {
      network = "projects/fixture-project/global/networks/fixture"
      subnet  = "projects/fixture-project/regions/us-central1/subnetworks/fixture"
    }
  }
  service_account       = "fixture@fixture-project.iam.gserviceaccount.com"
  notification_channels = []
  team                  = "fixture"
  product               = "fixture"
  containers = {
    "main" = {
      source = {
        working_dir = "."
        importpath  = "example.com/fixture/cmd/app"
      }
      ports = [{ container_port = 8080 }]
    }
  }
  primary-region    = "us-central1"
  octo_sts_identity = "fixture"
  broker = {
    "us-central1" = "projects/other/topics/shared-us-central1"
    "us-east4"    = "projects/other/topics/shared-us-east4"
    "us-west1"    = "projects/other/topics/shared-us-west1"
  }
  filters = [{}]

}



run "default_retains_issue_and_pr_intake" {
  command = plan

  assert {
    condition     = module.reconciler.dispatch_paused == null
    error_message = "Default issue/PR callers must preserve existing dispatcher scheduling behavior."
  }

  assert {
    condition = (
      var.deletion_protection &&
      !module.cloudevents-issues[0].subscriber_deletion_protection &&
      !module.cloudevents-prs[0].subscriber_deletion_protection
    )
    error_message = "Protecting the reconciler must leave both intake bridges removable by pause."
  }

  assert {
    condition = (
      length(module.cloudevents-issues[0].trigger_targets) == 1 &&
      length(module.cloudevents-prs[0].trigger_targets) == 5
    )
    error_message = "Default callers must retain regional issue and own-PR subscriptions."
  }
}

run "fan_in_delivers_all_broker_regions" {
  command = plan

  variables {
    fan_in_region = "us-central1"
  }

  assert {
    condition = (
      length(module.cloudevents-issues[0].trigger_targets) == 3 &&
      length(module.cloudevents-prs[0].trigger_targets) == 15 &&
      alltrue([
        for target in concat(values(module.cloudevents-issues[0].trigger_targets), values(module.cloudevents-prs[0].trigger_targets)) :
        target.target == "us-central1"
      ])
    )
    error_message = "Every broker region must deliver issue and own-PR events to the serving region."
  }
}

run "paused_retains_no_intake_subscriptions" {
  command = plan

  variables {
    fan_in_region = "us-central1"
    paused        = true
  }

  assert {
    condition     = length(module.cloudevents-issues) == 0 && length(module.cloudevents-prs) == 0
    error_message = "A paused reconciler must have neither issue nor PR intake subscriptions."
  }

  assert {
    condition     = module.reconciler.dispatch_paused
    error_message = "Pause must reach the child workqueue dispatcher as well as issue and PR intake."
  }
}
