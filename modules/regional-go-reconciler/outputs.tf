/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

output "receiver" {
  description = "The workqueue receiver object for connecting triggers."
  depends_on  = [module.receiver-service]
  value = {
    name = local.receiver_service_name
  }
}

output "reconciler-uris" {
  description = "The URIs of the reconciler service by region (short mode only)."
  value       = var.mode == "short" ? module.reconciler[0].uris : {}
}

output "bucket" {
  description = "The name of the GCS bucket backing the workqueue."
  value       = google_storage_bucket.global-workqueue.name
}
