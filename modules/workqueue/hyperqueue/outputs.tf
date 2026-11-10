/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

output "tag_binding_parents" {
  description = "The parent of every shard workqueue Pub/Sub tag binding, keyed by shard."
  value       = { for k, wq in module.workqueue : k => wq.tag_binding_parents }
}

output "receiver" {
  depends_on  = [module.hyperqueue-service]
  description = "The hyperqueue router service (clients queue work here)"
  value = {
    name = "${var.name}-hq"
  }
}
