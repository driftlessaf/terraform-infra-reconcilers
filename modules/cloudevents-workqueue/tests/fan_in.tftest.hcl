# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

# Plan-only tests through the real child modules with mocked providers. The
# subscriber runs in one region and the broker publishes to three, as for a
# single-region project reading a three-region broker in another project.
mock_provider "ko" {}
mock_provider "cosign" {}
mock_provider "google" {}
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
  }
  broker = {
    "us-central1" = "projects/other/topics/shared-us-central1"
    "us-east4"    = "projects/other/topics/shared-us-east4"
    "us-west1"    = "projects/other/topics/shared-us-west1"
  }
  filters = [
    { subject = "org/repo", type = "dev.chainguard.github.pull_request" },
    { subject = "org/repo", type = "dev.chainguard.github.check_run", action = "completed" },
  ]
  extension_key         = "pullrequesturl"
  workqueue             = { name = "fixture-rcv" }
  notification_channels = []
  team                  = "fixture"
}

run "other_broker_regions_ignored_by_default" {
  command = plan

  assert {
    condition     = toset(keys(module.trigger)) == toset(["us-central1-0", "us-central1-1"])
    error_message = "without fan_in_region, only the subscriber's own regions get triggers"
  }

  assert {
    condition     = alltrue([for t in values(local.trigger_index) : t.target == t.region])
    error_message = "without fan_in_region, every trigger must deliver to its own region"
  }
}

run "fan_in_subscribes_every_broker_region" {
  command = plan

  variables {
    fan_in_region = "us-central1"
  }

  assert {
    condition = toset(keys(module.trigger)) == toset([
      "us-central1-0", "us-central1-1",
      "us-east4-0", "us-east4-1",
      "us-west1-0", "us-west1-1",
    ])
    error_message = "every broker region must get the full set of triggers, keyed by broker region"
  }

  assert {
    condition     = alltrue([for t in values(local.trigger_index) : t.target == "us-central1"])
    error_message = "every trigger must deliver to the fan_in_region subscriber"
  }

  assert {
    condition = alltrue([
      for k, t in local.trigger_index : t.broker == "projects/other/topics/shared-${t.region}"
    ])
    error_message = "each trigger must subscribe to its own broker region's topic"
  }
}

run "fan_in_keeps_existing_triggers" {
  command = plan

  variables {
    fan_in_region = "us-central1"
  }

  # The us-central1 entries are what a caller without fan_in_region plans, so
  # turning it on adds triggers and changes none.
  assert {
    condition = alltrue([
      for k in ["us-central1-0", "us-central1-1"] :
      local.trigger_index[k].region == "us-central1" &&
      local.trigger_index[k].index == tonumber(split("-", k)[2]) &&
      local.trigger_index[k].suffix == ""
    ])
    error_message = "the subscriber region's trigger keys, indexes and names must not change"
  }
}

run "fan_in_covers_extra_brokers" {
  command = plan

  variables {
    fan_in_region = "us-central1"
    extra_brokers = {
      "dev.chainguard.github.check_run" = {
        "us-central1" = "projects/other/topics/check-run-us-central1"
        "us-east4"    = "projects/other/topics/check-run-us-east4"
        "us-west1"    = "projects/other/topics/check-run-us-west1"
      }
    }
  }

  assert {
    condition = toset(keys(local.extra_trigger_index)) == toset([
      "us-central1-1-x-dev.chainguard.github.check_run",
      "us-east4-1-x-dev.chainguard.github.check_run",
      "us-west1-1-x-dev.chainguard.github.check_run",
    ])
    error_message = "the check_run filter must get a dedicated-topic trigger in every broker region"
  }

  assert {
    condition = alltrue([
      for t in values(local.extra_trigger_index) :
      t.target == "us-central1" && t.broker == "projects/other/topics/check-run-${t.region}"
    ])
    error_message = "dedicated-topic triggers must read their region's topic and deliver to the fan_in_region subscriber"
  }
}

run "fan_in_drop_needs_a_topic_in_every_broker_region" {
  command = plan

  variables {
    fan_in_region = "us-central1"
    extra_brokers = {
      "dev.chainguard.github.check_run" = {
        "us-central1" = "projects/other/topics/check-run-us-central1"
      }
    }
    drop_shared_types = ["dev.chainguard.github.check_run"]
  }

  expect_failures = [google_service_account.subscriber]
}

run "fan_in_region_must_be_a_subscriber_region" {
  command = plan

  variables {
    fan_in_region = "us-east4"
  }

  expect_failures = [var.fan_in_region]
}
