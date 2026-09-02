/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

terraform {
  required_providers {
    ko     = { source = "ko-build/ko" }
    cosign = { source = "chainguard-dev/cosign" }
  }
}

// Stand up the reconciler service (short mode only).
// In long mode the reconciler runs as a sidecar in a Cloud Run Job instead.
module "reconciler" {
  count              = var.mode == "short" ? 1 : 0
  source             = "chainguard-dev/common/infra//modules/regional-go-service"
  observability_role = var.observability_role

  project_id = var.project_id
  name       = "${var.name}-rec"
  regions    = var.regions
  ingress    = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  egress     = var.egress

  deletion_protection = var.deletion_protection

  service_account = var.service_account
  containers      = local.containers_plus_trace_env

  labels           = merge({ "service" : "${var.name}-rec" }, var.labels)
  team             = var.team
  product          = var.product
  scaling          = var.scaling
  volumes          = var.volumes
  regional-volumes = var.regional-volumes
  enable_profiler  = var.enable_profiler
  otel_resources   = local.otel_resources

  # Reconciler and dispatcher run as the shared var.service_account. When the
  # caller manages that SA's observability grants itself, suppress the per-service
  # grants here to avoid overlapping non-authoritative IAM members.
  enable_observability_iam = var.enable_observability_iam

  request_timeout_seconds = var.request_timeout_seconds
  execution_environment   = var.execution_environment
  launch_stage            = var.launch_stage

  slo = var.slo

  notification_channels = var.notification_channels

  resource_manager_tags = var.resource_manager_tags
  version               = "1.38.1"
}
