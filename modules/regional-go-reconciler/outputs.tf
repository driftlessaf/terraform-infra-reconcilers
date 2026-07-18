/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

output "receiver" {
  description = "The workqueue receiver object for connecting triggers. When sharded, this is the hyperqueue router."
  depends_on  = [module.receiver-service, module.workqueue-sharded]
  value = var.shards > 1 ? module.workqueue-sharded[0].receiver : {
    name = local.receiver_service_name
  }
}

output "reconciler-uris" {
  description = "The URIs of the reconciler service by region (short mode only)."
  value       = var.mode == "short" ? module.reconciler[0].uris : {}
}

output "bucket" {
  description = "The name of the GCS bucket backing the workqueue (null when sharded; each shard manages its own bucket)."
  value       = var.shards > 1 ? null : google_storage_bucket.global-workqueue[0].name
}
