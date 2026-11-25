/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

output "receiver" {
  description = "The workqueue receiver object for connecting triggers."
  value       = module.reconciler.receiver
}

output "dispatch_paused" {
  description = "Configured automatic-dispatch pause; null preserves existing scheduler management."
  value       = module.reconciler.dispatch_paused
}

output "intake_targets" {
  description = "Issue and PR event targets by source region; empty while paused."
  value = {
    issues = try(module.cloudevents-issues[0].trigger_targets, {})
    prs    = try(module.cloudevents-prs[0].trigger_targets, {})
  }
}
