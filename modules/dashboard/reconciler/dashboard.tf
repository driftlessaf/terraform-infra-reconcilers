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
  source = "../../../../../public/terraform-infra-common/modules/dashboard/sections/workqueue"

  title           = "Workqueue State"
  service_name    = local.workqueue_name
  dispatcher_name = var.mode == "long" ? local.service_name : ""
  max_retry       = var.max_retry
  concurrent_work = var.concurrent_work
  shards          = var.shards
  filter          = []
  collapsed       = false
}

// Reconciler service sections
module "errgrp" {
  source       = "../../../../../public/terraform-infra-common/modules/dashboard/sections/errgrp"
  title        = "Reconciler Error Reporting"
  project_id   = var.project_id
  service_name = local.service_name
  collapsed    = true
}

module "reconciler-logs" {
  source        = "../../../../../public/terraform-infra-common/modules/dashboard/sections/logs"
  title         = "Reconciler Logs"
  filter        = [var.mode == "long" ? "resource.labels.job_name=\"${local.service_name}\"" : "resource.labels.service_name=\"${local.service_name}\""]
  cloudrun_type = var.mode == "long" ? "job" : "service"
}

module "http" {
  source       = "../../../../../public/terraform-infra-common/modules/dashboard/sections/http"
  title        = "HTTP"
  filter       = []
  service_name = local.service_name
}

module "grpc" {
  source       = "../../../../../public/terraform-infra-common/modules/dashboard/sections/grpc"
  title        = "GRPC"
  filter       = []
  service_name = local.service_name
}

module "github" {
  source = "../../../../../public/terraform-infra-common/modules/dashboard/sections/github"
  title  = "GitHub API"
  filter = []
}

module "agents" {
  source = "../../../../../public/terraform-infra-common/modules/dashboard/sections/agents"
  title  = "Agent Metrics"
  filter = [
    "metric.label.\"service_name\"=\"${local.service_name}\""
  ]
}

// When var.sections.microvm is set to a namespace, surface two collapsible groups: the
// control-plane metrics this reconciler's microvm.Manager records (scoped by
// service_name) and the agent-pod metrics scoped to that namespace.
module "microvm" {
  count  = var.sections.microvm != null ? 1 : 0
  source = "../../../../../public/terraform-infra-common/modules/dashboard/sections/microvm"
  filter = [
    "metric.label.\"service_name\"=\"${local.service_name}\""
  ]
  namespace = var.sections.microvm
}

module "resources" {
  source                = "../../../../../public/terraform-infra-common/modules/dashboard/sections/resources"
  title                 = "Reconciler Resources"
  filter                = []
  cloudrun_name         = local.service_name
  cloudrun_type         = var.mode == "long" ? "job" : "service"
  notification_channels = var.notification_channels
}

module "alerts" {
  for_each = var.alerts

  source = "../../../../../public/terraform-infra-common/modules/dashboard/sections/alerts"
  alert  = each.value
  title  = "Alert: ${each.key}"
}

module "width" { source = "../../../../../public/terraform-infra-common/modules/dashboard/sections/width" }

module "layout" {
  source = "../../../../../public/terraform-infra-common/modules/dashboard/sections/layout"
  sections = concat(
    [for x in keys(var.alerts) : module.alerts[x].section],
    [
      module.workqueue-state.section,
      module.errgrp.section,
      module.reconciler-logs.section,
    ],
    var.mode == "short" ? [module.http.section] : [],
    [module.grpc.section],
    var.sections.github ? [module.github.section] : [],
    var.sections.agents ? [module.agents.section] : [],
    var.sections.microvm != null ? module.microvm[0].sections : [],
    [module.resources.section],
  )
}

module "dashboard" {
  source = "../../../../../public/terraform-infra-common/modules/dashboard"

  object = {
    displayName = "Reconciler: ${var.name}"
    labels = merge({
      "service" : ""
      "reconciler" : ""
    }, var.labels)
    dashboardFilters = var.mode == "long" ? [
      {
        # Cloud Run Jobs use job_name as the resource label
        filterType  = "RESOURCE_LABEL"
        stringValue = local.service_name
        labelKey    = "job_name"
      },
      ] : [
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
}
