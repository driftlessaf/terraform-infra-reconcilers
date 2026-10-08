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

// Shaped for the workqueue module's reconciler-service input, so a caller
// attaching a second workqueue to this reconciler -- a priority lane, say --
// can order its roles/run.invoker grant after the service exists by passing
// this through, rather than by writing depends_on = [module.<this>].
//
// The distinction is the point. depends_on against a module makes every
// resource in the caller's queue depend on every resource in this one, and
// apply records that breadth in each resource's state dependencies, where it
// outlives the config that wrote it; a later plan with a destroy on one side
// and a replacement on the other turns those recorded edges into a graph
// cycle. The value below carries a narrow edge instead: in short mode
// local.reconciler_service_name is read off module.reconciler's output rather
// than rebuilt as a string, for exactly this reason.
//
// In long mode the reconciler is a Job rather than a Service, the name is a
// literal with no edge behind it, and there is no service to grant on. A
// caller attaching a workqueue there is already past what this can order.
output "reconciler-service" {
  description = "The reconciler that workqueue dispatchers deliver to, shaped for the workqueue module's reconciler-service input. In short mode the value depends on the reconciler Cloud Run service; in long mode the reconciler is a Job and the name is a literal."
  value = {
    name = local.reconciler_service_name
  }
}
