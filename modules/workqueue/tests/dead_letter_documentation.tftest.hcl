# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

mock_provider "google" {
  mock_data "google_project" {
    defaults = {
      number = "123456789"
    }
  }
}
mock_provider "google-beta" {}
mock_provider "null" {}
mock_provider "random" {
  mock_resource "random_string" {
    override_during = plan
    defaults = {
      result = "abc123"
    }
  }
}

variables {
  project_id = "fixture-project"
  name       = "fixture"
  regions = {
    "us-central1" = {
      network = "projects/fixture-project/global/networks/fixture"
      subnet  = "projects/fixture-project/regions/us-central1/subnetworks/fixture"
    }
  }
  concurrent-work = 1
  reconciler-service = {
    name = "fixture-reconciler"
  }
  team                  = "fixture"
  notification_channels = []
}

run "default_documentation_keeps_generic_guidance" {
  command = plan

  assert {
    condition     = startswith(google_monitoring_alert_policy.dead_letter_queue[0].documentation[0].content, "The `fixture` workqueue is holding")
    error_message = "An unset documentation input must leave the generic alert content first."
  }
}

run "custom_documentation_precedes_generic_guidance" {
  command = plan

  variables {
    dead_letter_alert_documentation = "Check the [service runbook](https://example.com/runbook) before retrying."
  }

  assert {
    condition     = startswith(google_monitoring_alert_policy.dead_letter_queue[0].documentation[0].content, "Check the [service runbook](https://example.com/runbook) before retrying.\n\nThe `fixture` workqueue is holding")
    error_message = "Service-specific precautions must precede the generic recovery steps."
  }

  assert {
    condition     = strcontains(google_monitoring_alert_policy.dead_letter_queue[0].documentation[0].content, "## Troubleshooting")
    error_message = "Custom guidance must not replace generic troubleshooting."
  }
}
