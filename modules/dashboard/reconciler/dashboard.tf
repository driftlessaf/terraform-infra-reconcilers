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
  dispatcher_name = var.mode == "long" ? local.service_name : ""
  max_retry       = var.max_retry
  concurrent_work = var.concurrent_work
  shards          = var.shards
  filter          = []
  collapsed       = false
  version         = "1.33.0"
}

// Reconciler service sections
module "errgrp" {
  source       = "chainguard-dev/common/infra//modules/dashboard/sections/errgrp"
  title        = "Reconciler Error Reporting"
  project_id   = var.project_id
  service_name = local.service_name
  collapsed    = true
  version      = "1.33.0"
}

module "reconciler-logs" {
  source        = "chainguard-dev/common/infra//modules/dashboard/sections/logs"
  title         = "Reconciler Logs"
  filter        = [var.mode == "long" ? "resource.labels.job_name=\"${local.service_name}\"" : "resource.labels.service_name=\"${local.service_name}\""]
  cloudrun_type = var.mode == "long" ? "job" : "service"
  version       = "1.33.0"
}

module "http" {
  source       = "chainguard-dev/common/infra//modules/dashboard/sections/http"
  title        = "HTTP"
  filter       = []
  service_name = local.service_name
  version      = "1.33.0"
}

module "grpc" {
  source       = "chainguard-dev/common/infra//modules/dashboard/sections/grpc"
  title        = "GRPC"
  filter       = []
  service_name = local.service_name
  version      = "1.33.0"
}

module "github" {
  source  = "chainguard-dev/common/infra//modules/dashboard/sections/github"
  title   = "GitHub API"
  filter  = []
  version = "1.33.0"
}

// The agents section's 12 widgets land on a dedicated dashboard
// (module.agents_dashboard below) rather than the main reconciler dashboard:
// combined with github they would push a reconciler past Cloud Monitoring's
// 50-widget-per-dashboard limit. The widgets are scoped by service_name.
module "agents" {
  source = "chainguard-dev/common/infra//modules/dashboard/sections/agents"
  title  = "Agent Metrics"
  filter = [
    "metric.label.\"service_name\"=\"${local.service_name}\""
  ]
  version = "1.33.0"
}

// When var.sections.microvm is set to a namespace, build two groups: the
// control-plane metrics this reconciler's microvm.Manager records (scoped by
// service_name) and the agent-pod metrics scoped to that namespace. These land
// on a dedicated dashboard (module.microvm_dashboard below) rather than the main
// reconciler dashboard: their 14 widgets would push reconcilers that also enable
// github+agents past Cloud Monitoring's 50-widget-per-dashboard limit.
module "microvm" {
  count  = var.sections.microvm != null ? 1 : 0
  source = "chainguard-dev/common/infra//modules/dashboard/sections/microvm"
  filter = [
    "metric.label.\"service_name\"=\"${local.service_name}\""
  ]
  namespace = var.sections.microvm
  // Expanded by default: the whole dedicated dashboard is about microvm.
  collapsed = false
  version   = "1.33.0"
}

module "resources" {
  source                = "chainguard-dev/common/infra//modules/dashboard/sections/resources"
  title                 = "Reconciler Resources"
  filter                = []
  cloudrun_name         = local.service_name
  cloudrun_type         = var.mode == "long" ? "job" : "service"
  notification_channels = var.notification_channels
  version               = "1.33.0"
}

module "alerts" {
  for_each = var.alerts

  source  = "chainguard-dev/common/infra//modules/dashboard/sections/alerts"
  alert   = each.value
  title   = "Alert: ${each.key}"
  version = "1.33.0"
}

module "width" {
  source  = "chainguard-dev/common/infra//modules/dashboard/sections/width"
  version = "1.33.0"
}

module "layout" {
  source = "chainguard-dev/common/infra//modules/dashboard/sections/layout"
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
    var.service_sections,
    [module.resources.section],
  )
  version = "1.33.0"
}

module "dashboard" {
  source = "chainguard-dev/common/infra//modules/dashboard"

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
  version = "1.33.0"
}

// microvm observability gets its own dashboard. Its control-plane and agent-pod
// groups are self-scoped per widget (service_name metric-label / namespace
// resource-label), so no dashboard-level filter is applied: a service_name
// filter would zero out the agent-pod widgets, which carry no reconciler
// service_name.
module "microvm_layout" {
  count    = var.sections.microvm != null ? 1 : 0
  source   = "chainguard-dev/common/infra//modules/dashboard/sections/layout"
  sections = module.microvm[0].sections
  version  = "1.33.0"
}

module "microvm_dashboard" {
  count  = var.sections.microvm != null ? 1 : 0
  source = "chainguard-dev/common/infra//modules/dashboard"

  object = {
    displayName = "Reconciler microvm: ${var.name}"
    labels = merge({
      "service" : ""
      "reconciler" : ""
      "microvm" : ""
    }, var.labels)

    // https://cloud.google.com/monitoring/api/ref_v3/rest/v1/projects.dashboards#mosaiclayout
    mosaicLayout = {
      columns = module.width.size
      tiles   = module.microvm_layout[0].tiles,
    }
  }
  version = "1.33.0"
}

// agents observability gets its own dashboard so its 12 widgets don't push a
// reconciler that also enables github past Cloud Monitoring's 50-widget limit.
// Unlike microvm, the agents section is scoped by service_name (see
// module.agents.filter), so this dashboard carries the SAME service_name
// dashboardFilters as the main reconciler dashboard; without them the agent
// widgets would not scope to this reconciler.
module "agents_layout" {
  count    = var.sections.agents ? 1 : 0
  source   = "chainguard-dev/common/infra//modules/dashboard/sections/layout"
  sections = [module.agents.section]
  version  = "1.33.0"
}

module "agents_dashboard" {
  count  = var.sections.agents ? 1 : 0
  source = "chainguard-dev/common/infra//modules/dashboard"

  object = {
    displayName = "Reconciler agents: ${var.name}"
    labels = merge({
      "service" : ""
      "reconciler" : ""
      "agents" : ""
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
      tiles   = module.agents_layout[0].tiles,
    }
  }
  version = "1.33.0"
}
