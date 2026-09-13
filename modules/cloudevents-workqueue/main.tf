terraform {
  required_providers {
    cosign = { source = "chainguard-dev/cosign" }
    google = { source = "hashicorp/google" }
    random = { source = "hashicorp/random" }
  }
}

module "subscriber-name" {
  source = "../../../../public/terraform-infra-common/modules/limited-concat"
  prefix = var.name
  suffix = "-sub"
  // https://cloud.google.com/iam/docs/service-accounts-create
  limit = 30
}

// Create a service account for the service
resource "google_service_account" "subscriber" {
  project = var.project_id

  account_id   = module.subscriber-name.result
  display_name = "CloudEvents to Workqueue Subscriber"
  description  = "Service account for ${var.name} CloudEvents subscriber"
}

// Deploy the subscriber service
module "subscriber" {
  source             = "../../../../public/terraform-infra-common/modules/regional-go-service"
  observability_role = var.observability_role

  project_id = var.project_id
  name       = var.name
  regions    = var.regions

  service_account = google_service_account.subscriber.email

  notification_channels = var.notification_channels
  deletion_protection   = var.deletion_protection

  team = var.team

  resource_manager_tags = var.resource_manager_tags

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
}

// Authorize the subscriber to call the workqueue in each region
module "subscriber-calls-workqueue" {
  for_each = var.regions

  source = "../../../../public/terraform-infra-common/modules/authorize-private-service"

  project_id      = var.project_id
  region          = each.key
  name            = var.workqueue.name
  service-account = google_service_account.subscriber.email
}

locals {
  // A Pub/Sub filter AND-composes its prefix clauses, so a set of prefixes that
  // should match as an OR needs one trigger per prefix. Normalize the singular
  // and plural inputs into one list; `[{}]` keeps the no-prefix case at exactly
  // one trigger per (region, filter).
  filter_prefix_sets = length(var.filter_prefixes) > 0 ? var.filter_prefixes : [var.filter_prefix]

  // Prefix is the outer dimension and filter the inner one, so the trigger index
  // of every existing (region, filter) pair is unchanged when a caller adds a
  // second prefix. Ordering it the other way would renumber the trailing filters
  // and destroy/recreate their live subscriptions.
  trigger_index = {
    for triple in setproduct(
      keys(var.regions),
      range(length(local.filter_prefix_sets)),
      range(length(var.filters))
    ) :
    "${triple[0]}-${triple[1] * length(var.filters) + triple[2]}" => {
      region = triple[0]
      filter = var.filters[triple[2]]
      prefix = local.filter_prefix_sets[triple[1]]
      index  = triple[1] * length(var.filters) + triple[2]
      broker = var.broker[triple[0]]
    }
  }
}

// Create a subscription to the broker with filters for the specified event types
// We need a trigger for each region, each filter, and each prefix set
module "trigger" {
  for_each = local.trigger_index

  source = "../../../../public/terraform-infra-common/modules/cloudevent-trigger"

  project_id = var.project_id
  name       = "${var.name}-${each.value.region}-${each.value.index}"
  broker     = each.value.broker

  private-service = {
    name   = var.name
    region = each.value.region
  }

  // Pass the filter and ensure extension key exists
  filter                = each.value.filter
  filter_prefix         = each.value.prefix
  filter_has_attributes = [var.extension_key]
  filter_not            = var.filter_not

  notification_channels = var.notification_channels

  max_delivery_attempts = var.max_delivery_attempts
  minimum_backoff       = var.minimum_backoff
  maximum_backoff       = var.maximum_backoff
  ack_deadline_seconds  = var.ack_deadline_seconds

  team = var.team

  resource_manager_tags = var.resource_manager_tags

  depends_on = [module.subscriber]
}
