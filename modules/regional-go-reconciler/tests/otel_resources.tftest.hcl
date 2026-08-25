# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

# Plan-only guard on how this module resolves the otel sidecar resource clause.
#
# regional-go-service supplies the shared default, but a module argument is
# always passed, so forwarding an unset var.otel_resources straight through
# clears that default and leaves the sidecar with no resource clause at all.
# These runs pin both halves of local.otel_resources: an unset caller lands on
# the shared default, and an explicit caller value is forwarded verbatim.
#
# The google providers are mocked so the plan stays offline: the real ones
# would try to load application default credentials.

mock_provider "ko" {}
mock_provider "cosign" {}
mock_provider "google" {}
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
}

run "unset_otel_resources_takes_the_module_default" {
  command = plan

  assert {
    condition = (
      local.otel_resources.limits.cpu == "250m" &&
      local.otel_resources.limits.memory == "512Mi"
    )
    error_message = "an unset otel_resources resolved to ${jsonencode(local.otel_resources)} instead of the 250m/512Mi module default"
  }
}

run "explicit_otel_resources_are_forwarded_verbatim" {
  command = plan

  variables {
    otel_resources = {
      limits = {
        cpu    = "1000m"
        memory = "1Gi"
      }
    }
  }

  assert {
    condition = (
      local.otel_resources.limits.cpu == "1000m" &&
      local.otel_resources.limits.memory == "1Gi"
    )
    error_message = "an explicit otel_resources override resolved to ${jsonencode(local.otel_resources)}"
  }
}
