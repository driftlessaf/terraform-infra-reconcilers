# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

# Plan-only guard on who may run the long-mode reconciler Job. The binding is
# authoritative, so reconciler_invokers is the only way to add a member, and
# the default must leave the Job's own invoker service account alone.

mock_provider "ko" {}
mock_provider "cosign" {}
mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

// The invoker account's member is only known after apply; fix it so the
// binding's members are known at plan.
override_resource {
  target          = module.reconciler-job[0].google_service_account.invoker
  override_during = plan
  values = {
    email  = "fixture-invoker@fixture-project.iam.gserviceaccount.com"
    member = "serviceAccount:fixture-invoker@fixture-project.iam.gserviceaccount.com"
  }
}

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
}

run "default_grants_only_the_invoker_account" {
  command = plan

  assert {
    condition     = toset(output.reconciler_invocation_grants["us-central1"].members) == toset(["serviceAccount:fixture-invoker@fixture-project.iam.gserviceaccount.com"])
    error_message = "with no reconciler_invokers the Job's run.invoker binding must hold only its invoker service account"
  }
}

run "reconciler_invokers_reach_the_job" {
  command = plan

  variables {
    reconciler_invokers = ["group:operators@example.com", "user:operator@example.com"]
  }

  assert {
    condition = toset(output.reconciler_invocation_grants["us-central1"].members) == toset([
      "serviceAccount:fixture-invoker@fixture-project.iam.gserviceaccount.com",
      "group:operators@example.com",
      "user:operator@example.com",
    ])
    error_message = "reconciler_invokers must be added to the Job's run.invoker binding next to its invoker service account"
  }
}

run "short_mode_has_no_job_grant" {
  command = plan

  variables {
    mode                = "short"
    reconciler_invokers = ["group:operators@example.com"]
  }

  assert {
    condition     = length(output.reconciler_invocation_grants) == 0
    error_message = "short mode has no reconciler Job, so it must expose no Job grant"
  }
}
