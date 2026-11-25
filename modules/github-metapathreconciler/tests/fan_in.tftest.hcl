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
  repos = [{
    owner               = "fixture"
    repo                = "fixture"
    path_patterns       = [".*"]
    resync_period_hours = 1
  }]
}

run "default_keeps_regional_pr_and_comment_subscriptions" {
  command = plan

  variables { pr_conversation_comments = true }

  assert {
    condition     = length(module.cloudevents-prs[0].trigger_targets) == 5 && length(module.cloudevents-pr-comments[0].trigger_targets) == 1
    error_message = "Default callers must retain the existing own-region PR and comment subscriptions."
  }
}

run "fan_in_covers_pr_and_comment_subscriptions" {
  command = plan

  variables {
    fan_in_region            = "us-central1"
    pr_conversation_comments = true
  }

  assert {
    condition = module.reconciler.push_trigger_targets == {
      "fixture/fixture/us-central1" = { region = "us-central1", target = "us-central1" }
      "fixture/fixture/us-east4"    = { region = "us-east4", target = "us-central1" }
      "fixture/fixture/us-west1"    = { region = "us-west1", target = "us-central1" }
    }
    error_message = "The meta-path module must deliver pushes from all three broker regions to its central listener."
  }

  assert {
    condition     = length(module.cloudevents-prs[0].trigger_targets) == 15 && length(module.cloudevents-pr-comments[0].trigger_targets) == 3
    error_message = "All five PR event types and conversation comments must be subscribed in every broker region."
  }

  assert {
    condition = alltrue([
      for t in concat(values(module.cloudevents-prs[0].trigger_targets), values(module.cloudevents-pr-comments[0].trigger_targets)) : t.target == "us-central1"
    ])
    error_message = "Every remote PR and conversation-comment trigger must deliver to the serving region."
  }
}

run "paused_keeps_pr_and_comment_subscriptions_off" {
  command = plan

  variables {
    fan_in_region            = "us-central1"
    pr_conversation_comments = true
    paused                   = true
  }

  assert {
    condition     = length(module.cloudevents-prs) == 0 && length(module.cloudevents-pr-comments) == 0
    error_message = "Fan-in must not subscribe paused PR or conversation-comment bridges."
  }
}

run "dispatch_pause_reaches_the_workqueue" {
  command = plan

  variables {
    paused          = true
    dispatch_paused = true
  }

  assert {
    condition     = module.reconciler.dispatch_paused == true
    error_message = "The explicit dispatcher pause must reach the path reconciler's real workqueue."
  }
}
