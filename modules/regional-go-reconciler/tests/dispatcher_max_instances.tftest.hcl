# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

# Plan-only guard that dispatcher_max_instances and dispatch_period reach the
# dispatcher service and leave the defaults when unset.

mock_provider "ko" {}
mock_provider "cosign" {}
mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  project_id = "fixture-project"
  name       = "fixture"
  mode       = "short"
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
}

run "dispatcher_instances_default_when_unset" {
  command = plan

  assert {
    condition = alltrue([
      local.dispatcher_scaling.max_instances == null,
      local.dispatcher_scaling.service_max_instances == null,
      one([for e in local.short_mode_dispatcher_env : e.value if e.name == "WORKQUEUE_DISPATCH_PERIOD"]) == "1s",
    ])
    error_message = "the dispatcher must keep the instance and dispatch period defaults unless set"
  }
}

run "dispatcher_instance_cap_is_forwarded" {
  command = plan

  variables {
    dispatcher_max_instances = 1
    dispatch_period          = "60s"
  }

  assert {
    condition = alltrue([
      local.dispatcher_scaling.max_instances == 1,
      local.dispatcher_scaling.service_max_instances == 1,
      one([for e in local.short_mode_dispatcher_env : e.value if e.name == "WORKQUEUE_DISPATCH_PERIOD"]) == "60s",
    ])
    error_message = "the configured dispatcher instance cap or dispatch period was not forwarded"
  }
}

run "fractional_dispatcher_instance_cap_is_rejected" {
  command = plan

  variables {
    dispatcher_max_instances = 1.5
  }

  expect_failures = [var.dispatcher_max_instances]
}

run "zero_dispatcher_instance_cap_is_rejected" {
  command = plan

  variables {
    dispatcher_max_instances = 0
  }

  expect_failures = [var.dispatcher_max_instances]
}

run "malformed_dispatch_period_is_rejected" {
  command = plan

  variables {
    dispatch_period = "1 minute"
  }

  expect_failures = [var.dispatch_period]
}

run "oversized_dispatch_period_is_rejected" {
  command = plan

  variables {
    dispatch_period = "9999999999m"
  }

  expect_failures = [var.dispatch_period]
}

run "sharded_dispatcher_settings_are_rejected" {
  command = plan

  variables {
    shards                   = 2
    dispatcher_max_instances = 1
    dispatch_period          = "60s"
  }

  expect_failures = [var.dispatcher_max_instances, var.dispatch_period]
}
