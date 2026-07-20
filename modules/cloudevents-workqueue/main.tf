terraform {
  required_providers {
    cosign = { source = "chainguard-dev/cosign" }
    google = { source = "hashicorp/google" }
    random = { source = "hashicorp/random" }
  }
}

// Create a service account for the service
resource "google_service_account" "subscriber" {
  project = var.project_id

  account_id   = "${var.name}-sub"
  display_name = "CloudEvents to Workqueue Subscriber"
  description  = "Service account for ${var.name} CloudEvents subscriber"
}

// Deploy the subscriber service
module "subscriber" {
  source             = "chainguard-dev/common/infra//modules/regional-go-service"
  observability_role = var.observability_role

  project_id = var.project_id
  name       = var.name
  regions    = var.regions

  service_account = google_service_account.subscriber.email

  notification_channels = var.notification_channels
  deletion_protection   = var.deletion_protection

  team = var.team

  containers = {
    "subscriber" = {
      source = {
        importpath  = "./cmd/subscriber"
        working_dir = path.module
      }
      ports = [{
        container_port = 8080
      }]
      env = [{
        name  = "EXTENSION_KEY"
        value = var.extension_key
        }, {
        name  = "PRIORITY"
        value = tostring(var.priority)
        }, {
        name  = "DELAY_SECONDS"
        value = tostring(var.delay_seconds)
      }]
      regional-env = [
        {
          name  = "WORKQUEUE_SERVICE"
          value = { for k, v in module.subscriber-calls-workqueue : k => v.uri }
        }
      ]
    }
  }
  version = "1.21.1"
}

// Authorize the subscriber to call the workqueue in each region
module "subscriber-calls-workqueue" {
  for_each = var.regions

  source = "chainguard-dev/common/infra//modules/authorize-private-service"

  project_id      = var.project_id
  region          = each.key
  name            = var.workqueue.name
  service-account = google_service_account.subscriber.email
  version         = "1.21.1"
}

// Create a subscription to the broker with filters for the specified event types
// We need a trigger for each region and each filter
module "trigger" {
  for_each = {
    for pair in setproduct(keys(var.regions), range(length(var.filters))) :
    "${pair[0]}-${pair[1]}" => {
      region = pair[0]
      filter = var.filters[pair[1]]
      index  = pair[1]
      broker = var.broker[pair[0]]
    }
  }

  source = "chainguard-dev/common/infra//modules/cloudevent-trigger"

  project_id = var.project_id
  name       = "${var.name}-${each.value.region}-${each.value.index}"
  broker     = each.value.broker

  private-service = {
    name   = var.name
    region = each.value.region
  }

  // Pass the filter and ensure extension key exists
  filter                = each.value.filter
  filter_prefix         = var.filter_prefix
  filter_has_attributes = [var.extension_key]
  filter_not            = var.filter_not

  notification_channels = var.notification_channels

  max_delivery_attempts = var.max_delivery_attempts
  minimum_backoff       = var.minimum_backoff
  maximum_backoff       = var.maximum_backoff
  ack_deadline_seconds  = var.ack_deadline_seconds

  team = var.team

  depends_on = [module.subscriber]
  version    = "1.21.1"
}
