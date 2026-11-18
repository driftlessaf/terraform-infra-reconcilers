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

run "default_keeps_regional_subscriptions" {
  command = plan

  assert {
    condition     = toset(keys(module.push-subscription)) == toset(["fixture/fixture/us-central1"]) && local.push_subscriptions["fixture/fixture/us-central1"].target == "us-central1"
    error_message = "Default callers must retain only their existing regional push subscription."
  }
}

run "fan_in_subscribes_all_broker_regions" {
  command = plan

  variables { fan_in_region = "us-central1" }

  assert {
    condition = toset(keys(module.push-subscription)) == toset([
      "fixture/fixture/us-central1", "fixture/fixture/us-east4", "fixture/fixture/us-west1",
    ])
    error_message = "Every broker region must have a repository-scoped push subscription."
  }

  assert {
    condition     = alltrue([for s in values(local.push_subscriptions) : s.target == "us-central1" && s.subject == "fixture/fixture"])
    error_message = "Remote push subscriptions must preserve repository filtering and deliver centrally."
  }

  assert {
    condition     = toset(keys(module.push-listener.names)) == toset(["us-central1"])
    error_message = "Fan-in must not deploy a listener in each broker region."
  }
}

run "discovered_repositories_use_every_broker_region" {
  command = plan

  variables {
    fan_in_region  = "us-central1"
    github_app_id  = 12345
    github_app_key = "gcpkms://fixture"
    repos          = []
  }

  assert {
    condition     = toset(keys(module.push-subscription)) == toset(["us-central1", "us-east4", "us-west1"]) && alltrue([for s in values(local.push_subscriptions) : s.target == "us-central1" && s.subject == null])
    error_message = "App-installation discovery must fan in every broker region without adding a repository filter."
  }
}

run "existing_listener_keeps_local_delivery" {
  command = plan

  variables {
    fan_in_region = "us-central1"
    regions = {
      "us-central1" = { network = "fixture", subnet = "central" }
      "us-east4"    = { network = "fixture", subnet = "east" }
    }
  }

  assert {
    condition     = local.push_subscriptions["fixture/fixture/us-east4"].target == "us-east4" && local.push_subscriptions["fixture/fixture/us-west1"].target == "us-central1"
    error_message = "Only broker regions without a listener may be redirected to the fan-in region."
  }
}

run "paused_keeps_subscriptions_off" {
  command = plan

  variables {
    fan_in_region = "us-central1"
    paused        = true
  }

  assert {
    condition     = length(module.push-subscription) == 0
    error_message = "Fan-in must not subscribe a paused reconciler."
  }
}

run "disabled_push_listener_keeps_subscriptions_off" {
  command = plan

  variables {
    fan_in_region        = "us-central1"
    enable_push_listener = false
  }

  assert {
    condition     = length(module.push-subscription) == 0
    error_message = "Fan-in must respect the push-listener opt-out."
  }
}

run "fan_in_region_must_have_a_listener" {
  command = plan

  variables {
    fan_in_region = "us-east4"
    paused        = true
  }

  expect_failures = [var.fan_in_region]
}
