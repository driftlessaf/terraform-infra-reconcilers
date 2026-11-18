/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

output "receiver" {
  description = "The workqueue receiver object for connecting triggers."
  value       = module.reconciler.receiver
}

output "bucket" {
  description = "The name of the GCS bucket backing the workqueue."
  value       = module.reconciler.bucket
}

output "receiver_uri" {
  description = "URI of the workqueue receiver in the primary region. service_account is already allowed to invoke it, so other jobs running as it can enqueue without their own grant."
  value       = module.reconciler.receiver_uri
}

output "push_trigger_targets" {
  description = "For each push subscription, the broker region and the push listener region that receives its events."
  value       = module.reconciler.push_trigger_targets
}
