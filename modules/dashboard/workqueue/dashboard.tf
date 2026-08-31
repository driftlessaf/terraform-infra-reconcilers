module "workqueue-state" {
  source = "chainguard-dev/common/infra//modules/dashboard/sections/workqueue"

  title           = "Workqueue State"
  service_name    = var.name
  max_retry       = var.max_retry
  concurrent_work = var.concurrent_work
  shards          = var.shards
  filter          = []
  collapsed       = false
  version         = "1.37.0"
}

module "receiver-logs" {
  source        = "chainguard-dev/common/infra//modules/dashboard/sections/logs"
  title         = "Receiver Logs"
  filter        = ["resource.labels.service_name=\"${var.name}-rcv\""]
  cloudrun_type = "service"
  version       = "1.37.0"
}

module "dispatcher-logs" {
  source        = "chainguard-dev/common/infra//modules/dashboard/sections/logs"
  title         = "Dispatcher Logs"
  filter        = ["resource.labels.service_name=\"${var.name}-dsp\""]
  cloudrun_type = "service"
  version       = "1.37.0"
}

module "alerts" {
  for_each = var.alerts

  source  = "chainguard-dev/common/infra//modules/dashboard/sections/alerts"
  alert   = each.value
  title   = "Alert: ${each.key}"
  version = "1.37.0"
}

module "width" {
  source  = "chainguard-dev/common/infra//modules/dashboard/sections/width"
  version = "1.37.0"
}

module "layout" {
  source = "chainguard-dev/common/infra//modules/dashboard/sections/layout"

  sections = concat(
    [for x in keys(var.alerts) : module.alerts[x].section],
    [
      module.workqueue-state.section,
      module.receiver-logs.section,
      module.dispatcher-logs.section,
    ]
  )
  version = "1.37.0"
}

module "dashboard" {
  source = "chainguard-dev/common/infra//modules/dashboard"

  object = {
    displayName = "Cloud Workqueue: ${var.name}"
    labels = merge({
      "service" : ""
      "workqueue" : ""
    }, var.labels)

    dashboardFilters = [
      {
        # for GCP Cloud Run built-in metrics
        filterType  = "RESOURCE_LABEL"
        stringValue = "${var.name}-rcv"
        labelKey    = "service_name"
      },
      {
        # for GCP Cloud Run built-in metrics
        filterType  = "RESOURCE_LABEL"
        stringValue = "${var.name}-dsp"
        labelKey    = "service_name"
      },
      {
        # for Prometheus user added metrics - receiver
        filterType  = "METRIC_LABEL"
        stringValue = "${var.name}-rcv"
        labelKey    = "service_name"
      },
      {
        # for Prometheus user added metrics - dispatcher
        filterType  = "METRIC_LABEL"
        stringValue = "${var.name}-dsp"
        labelKey    = "service_name"
      },
    ]

    // https://cloud.google.com/monitoring/api/ref_v3/rest/v1/projects.dashboards#mosaiclayout
    mosaicLayout = {
      columns = module.width.size
      tiles   = module.layout.tiles,
    }
  }
  version = "1.37.0"
}
