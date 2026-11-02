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
  broker            = { "us-central1" = "fixture-broker" }
  repos = [{
    owner               = "fixture"
    repo                = "fixture"
    path_patterns       = [".*"]
    resync_period_hours = 1
  }]
}

run "off_by_default" {
  command = plan

  assert {
    condition     = local.pr_comments_enabled == false
    error_message = "conversation comment events must be opt-in"
  }

  assert {
    condition     = length(local.pr_event_types) == 5
    error_message = "the default event list must not change"
  }

  assert {
    condition     = !contains([for t in local.pr_event_types : t.type], "dev.chainguard.github.issue_comment")
    error_message = "issue_comment must not join the default event list"
  }

  assert {
    condition     = length(module.cloudevents-pr-comments) == 0
    error_message = "no comment trigger set may be created when the flag is off"
  }
}

run "on_adds_one_scoped_trigger_set" {
  command = plan

  variables {
    pr_conversation_comments = true
  }

  assert {
    condition     = local.pr_comments_enabled == true
    error_message = "the flag must enable the comment trigger set"
  }

  assert {
    condition = local.pr_comment_filters == [tomap({
      subject = "fixture/fixture"
      type    = "dev.chainguard.github.issue_comment"
      action  = "created"
    })]
    error_message = "comment events must be limited to created, per repo"
  }

  assert {
    condition     = local.pr_comment_filter_not == [{ key = "actortype", value = "Bot" }]
    error_message = "comment events from bots must be dropped: this clause stops the reconciler's own replies from waking it"
  }

  assert {
    condition     = length(local.pr_event_types) == 5
    error_message = "the default event list must not change when the flag is on"
  }

  assert {
    condition     = length(module.cloudevents-pr-comments) == 1
    error_message = "the flag must add exactly one comment trigger set"
  }
}

run "paused_wins" {
  command = plan

  variables {
    pr_conversation_comments = true
    paused                   = true
  }

  assert {
    condition     = local.pr_comments_enabled == false
    error_message = "a paused reconciler must not subscribe to comment events"
  }

  assert {
    condition     = length(module.cloudevents-pr-comments) == 0
    error_message = "a paused reconciler must not create a comment trigger set"
  }
}
