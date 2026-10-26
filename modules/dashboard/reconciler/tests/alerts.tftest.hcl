# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

# var.alerts went untested for as long as it went unused: it was typed as a map
# of objects but handed to dashboard/sections/alerts, whose input is a string,
# so the first caller to populate it would have failed at plan. These runs
# exercise a populated map end to end — module -> section -> alertChart widget
# -> rendered dashboard JSON — so the shape cannot drift apart again.
#
# The google provider is mocked so the plan stays offline: no credentials, no
# state, no API calls.

mock_provider "google" {}

variables {
  project_id = "fixture-project"
  name       = "fixture"
}

# The default every caller in the tree uses today. Nothing named "Alert:" lands
# on the board.
run "empty_alerts_render_no_chart" {
  command = plan

  assert {
    condition     = !strcontains(output.json, "alertChart")
    error_message = "the default empty alerts map must add no alert chart"
  }
}

# A populated map plans, and each entry becomes an alertChart keyed by the
# policy id with the map key as its title.
run "populated_alerts_render_charts" {
  command = plan

  variables {
    alerts = {
      "Dead letter" = "projects/fixture-project/alertPolicies/1111111111111111111"
      "Work age"    = "projects/fixture-project/alertPolicies/2222222222222222222"
    }
  }

  assert {
    condition     = strcontains(output.json, "\"alertChart\":{\"name\":\"projects/fixture-project/alertPolicies/1111111111111111111\"}")
    error_message = "the first alert's policy id must reach the rendered alertChart"
  }

  assert {
    condition     = strcontains(output.json, "\"alertChart\":{\"name\":\"projects/fixture-project/alertPolicies/2222222222222222222\"}")
    error_message = "the second alert's policy id must reach the rendered alertChart"
  }

  assert {
    condition     = strcontains(output.json, "\"title\":\"Alert: Dead letter\"")
    error_message = "the map key must title the alert chart"
  }
}
