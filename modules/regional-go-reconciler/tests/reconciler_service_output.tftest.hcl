# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

# The reconciler-service output exists so a caller attaching its own workqueue
# to this reconciler gets a dependency edge to the reconciler service alone,
# instead of reaching for depends_on against the whole module.
#
# What these runs pin is the name, in both modes. They do not pin the edge,
# which is the reason the output exists: a dependency is a property of the
# graph, and an assert can only read values. The edge is kept honest by
# local.reconciler_service_name reading off module.reconciler's output in short
# mode rather than rebuilding the string — so a regression that broke the edge
# would almost certainly also break these names, and that is the whole of the
# coverage claimed here.

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

run "short_mode_names_the_reconciler_service" {
  command = plan

  assert {
    condition     = output.reconciler-service.name == "fixture-rec"
    error_message = "the output must name the reconciler Cloud Run service a caller's dispatcher is granted run.invoker on"
  }
}

run "long_mode_names_the_reconciler_job" {
  command = plan

  variables {
    mode = "long"
  }

  # Long mode has no reconciler Service to grant on -- the reconciler is a Job,
  # and the module's own dispatcher_calls_target_enabled is false there. The
  # output still resolves, to the job's name, so a caller reading it does not
  # have to branch on mode; it just carries no edge, because there is nothing
  # for it to wait on.
  assert {
    condition     = output.reconciler-service.name == "fixture-rec"
    error_message = "the output must still resolve in long mode, to the reconciler job's name"
  }
}
