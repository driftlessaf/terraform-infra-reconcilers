/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

// Authorize the reconciler's service account to publish agent-trace
// CloudEvents to the trace ingress. Provisioned only when trace_event_ingress
// is set; absent it, the containers get no EVENT_INGRESS_URI and agenttrace
// emission in the binary degrades to a no-op.
module "reconciler-publishes-traces" {
  for_each = local.trace_event_ingress != null ? local.regions : {}

  source = "chainguard-dev/common/infra//modules/authorize-private-service"

  project_id      = local.project_id
  region          = each.key
  name            = local.trace_event_ingress.name
  service-account = var.service_account
  version         = "1.25.2"
}

locals {
  // EVENT_INGRESS_URI entry appended to every reconciler container when the
  // trace ingress is wired; empty otherwise.
  trace_regional_env = local.trace_event_ingress != null ? [{
    name  = "EVENT_INGRESS_URI"
    value = { for k, v in module.reconciler-publishes-traces : k => v.uri }
  }] : []

  // var.containers with the trace env appended, consumed by both the
  // short-mode service (main.tf) and the long-mode job (reconciler-job.tf)
  // so the wiring is identical in either mode.
  containers_plus_trace_env = { for k, v in var.containers : k => merge(v, {
    regional-env = concat(v.regional-env, local.trace_regional_env)
  }) }
}
