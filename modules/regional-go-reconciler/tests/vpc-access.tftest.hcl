# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

# Plan-only tests pinning that var.regional-connector actually reaches the
# receiver and reconciler services this module stands up, mirroring
# regional-service's own vpc-access.tftest.hcl one level down.
#
# This module never renders vpc_access itself — it forwards regional-connector
# into regional-go-service (receiver, dispatcher, reconciler) and
# regional-go-cron (long-mode reconciler-job). A forwarding var dropped on the
# floor here fails exactly the way the original webhook connector PR called
# out as its own known gap: silently, with no plan or apply error, and a
# region left on direct VPC egress that a Shared VPC's Cloud NAT never
# translates.
#
# Mock providers keep this fully offline: no credentials, no state.

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

# regional-go-service and regional-service (three module hops down from here)
# expose no output that surfaces the rendered vpc_access block, so a plan-time
# assertion can't inspect the receiver/reconciler service's actual
# network_interfaces vs. connector wiring from this module's own tests — that
# coverage lives in regional-service/tests/vpc-access.tftest.hcl instead. A
# malformed connector id does prove the value reaches regional-service's own
# validation (confirmed manually: it fails on all three composed services),
# but Terraform's expect_failures does not attribute a child module's
# validation error back to this module's same-named variable, so that
# negative case can't be expressed as a passing test here without a false
# "unexpected error" failure. This positive case is what's left achievable:
# a well-formed connector must not break the plan for any composed service.
run "well_formed_connector_plans_cleanly" {
  command = plan

  variables {
    regional-connector = {
      "us-central1" = "projects/host-project/locations/us-central1/connectors/cr-egress-us-central1"
    }
  }
}
