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
