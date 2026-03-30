/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

locals {
  service_name   = var.service_name != "" ? var.service_name : "${var.name}-rec"
  workqueue_name = var.workqueue_name != "" ? var.workqueue_name : "${var.name}-wq"
}

// Workqueue metrics section
module "workqueue-state" {
  source = "chainguard-dev/common/infra//modules/dashboard/sections/workqueue"

  title           = "Workqueue State"
  service_name    = local.workqueue_name
  max_retry       = var.max_retry
  concurrent_work = var.concurrent_work
  shards          = var.shards
  filter          = []
  collapsed       = false
  version         = "1.0.2"
}

// Reconciler service sections
module "errgrp" {
  source       = "chainguard-dev/common/infra//modules/dashboard/sections/errgrp"
  title        = "Reconciler Error Reporting"
  project_id   = var.project_id
  service_name = local.service_name
  collapsed    = true
  version      = "1.0.2"
}

module "reconciler-logs" {
  source        = "chainguard-dev/common/infra//modules/dashboard/sections/logs"
  title         = "Reconciler Logs"
  filter        = ["resource.labels.service_name=\"${local.service_name}\""]
  cloudrun_type = "service"
  version       = "1.0.2"
}

module "http" {
  source       = "chainguard-dev/common/infra//modules/dashboard/sections/http"
  title        = "HTTP"
  filter       = []
  service_name = local.service_name
  version      = "1.0.2"
}

module "grpc" {
  source       = "chainguard-dev/common/infra//modules/dashboard/sections/grpc"
  title        = "GRPC"
  filter       = []
  service_name = local.service_name
  version      = "1.0.2"
}

module "github" {
  source  = "chainguard-dev/common/infra//modules/dashboard/sections/github"
  title   = "GitHub API"
  filter  = []
  version = "1.0.2"
}

module "agents" {
  source = "chainguard-dev/common/infra//modules/dashboard/sections/agents"
  title  = "Agent Metrics"
  filter = [
    "metric.label.\"service_name\"=\"${local.service_name}\""
  ]
  version = "1.0.2"
}

module "resources" {
  source                = "chainguard-dev/common/infra//modules/dashboard/sections/resources"
  title                 = "Reconciler Resources"
  filter                = []
  cloudrun_name         = local.service_name
  cloudrun_type         = "service"
  notification_channels = var.notification_channels
  version               = "1.0.2"
}

module "alerts" {
  for_each = var.alerts

  source  = "chainguard-dev/common/infra//modules/dashboard/sections/alerts"
  alert   = each.value
  title   = "Alert: ${each.key}"
  version = "1.0.2"
}

module "width" {
  source  = "chainguard-dev/common/infra//modules/dashboard/sections/width"
  version = "1.0.2"
}

module "layout" {
  source = "chainguard-dev/common/infra//modules/dashboard/sections/layout"
  sections = concat(
    [for x in keys(var.alerts) : module.alerts[x].section],
    [
      module.workqueue-state.section,
      module.errgrp.section,
      module.reconciler-logs.section,
      module.http.section,
      module.grpc.section,
    ],
    var.sections.github ? [module.github.section] : [],
    var.sections.agents ? [module.agents.section] : [],
    [module.resources.section],
  )
  version = "1.0.2"
}

module "dashboard" {
  source = "chainguard-dev/common/infra//modules/dashboard"

  object = {
    displayName = "Reconciler: ${var.name}"
    labels = merge({
      "service" : ""
      "reconciler" : ""
    }, var.labels)
    dashboardFilters = [
      {
        # for GCP Cloud Run built-in metrics
        filterType  = "RESOURCE_LABEL"
        stringValue = local.service_name
        labelKey    = "service_name"
      },
      {
        # for Prometheus user added metrics
        filterType  = "METRIC_LABEL"
        stringValue = local.service_name
        labelKey    = "service_name"
      },
    ]

    // https://cloud.google.com/monitoring/api/ref_v3/rest/v1/projects.dashboards#mosaiclayout
    mosaicLayout = {
      columns = module.width.size
      tiles   = module.layout.tiles,
    }
  }
  version = "1.0.2"
}
