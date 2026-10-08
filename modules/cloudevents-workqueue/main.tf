terraform {
  required_providers {
    cosign = { source = "chainguard-dev/cosign" }
    google = { source = "hashicorp/google" }
    random = { source = "hashicorp/random" }
    # Declare transitive providers so test mocks attach at this module's root.
    ko          = { source = "ko-build/ko" }
    google-beta = { source = "hashicorp/google-beta" }
  }
}

module "subscriber-name" {
  source = "chainguard-dev/common/infra//modules/limited-concat"
  prefix = var.name
  suffix = "-sub"
  // https://cloud.google.com/iam/docs/service-accounts-create
  limit   = 30
  version = "1.58.2"
}

// Create a service account for the service
resource "google_service_account" "subscriber" {
  project = var.project_id

  account_id   = module.subscriber-name.result
  display_name = "CloudEvents to Workqueue Subscriber"
  description  = "Service account for ${var.name} CloudEvents subscriber"

  lifecycle {
    # Dropping a shared trigger without a dedicated one in its region would
    # stop delivery of that type there.
    precondition {
      condition = alltrue([
        for t in local.dropped_shared_triggers : can(var.extra_brokers[t.filter.type][t.region])
      ])
      error_message = "each drop_shared_types entry must have an extra_brokers topic in every region whose shared trigger it drops."
    }
  }
}

// Deploy the subscriber service
module "subscriber" {
  source             = "chainguard-dev/common/infra//modules/regional-go-service"
  observability_role = var.observability_role

  project_id = var.project_id
  name       = var.name
  regions    = var.regions

  service_account = google_service_account.subscriber.email
  scaling         = var.scaling

  notification_channels = var.notification_channels
  deletion_protection   = var.deletion_protection

  team    = var.team
  product = var.product

  resource_manager_tags = var.resource_manager_tags

  containers = {
    "subscriber" = {
      source = {
        importpath  = var.subscriber_source == null ? "./cmd/subscriber" : var.subscriber_source.importpath
        working_dir = var.subscriber_source == null ? path.module : var.subscriber_source.working_dir
      }
      ports = [{
        container_port = 8080
      }]
      env = concat([{
        name  = "EXTENSION_KEY"
        value = var.extension_key
        }, {
        name  = "PRIORITY"
        value = tostring(var.priority)
        }, {
        name  = "DELAY_SECONDS"
        value = tostring(var.delay_seconds)
      }], var.subscriber_extra_env)
      regional-env = [
        {
          name  = "WORKQUEUE_SERVICE"
          value = { for k, v in module.subscriber-calls-workqueue : k => v.uri }
        }
      ]
    }
  }
  version = "1.58.2"
}

// Authorize the subscriber to call the workqueue in each region
module "subscriber-calls-workqueue" {
  for_each = var.regions

  source = "chainguard-dev/common/infra//modules/authorize-private-service"

  project_id      = var.project_id
  region          = each.key
  name            = var.workqueue.name
  service-account = google_service_account.subscriber.email
  version         = "1.58.2"
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
      suffix = ""
    }
  }

  // Parallel triggers on the dedicated topics in var.extra_brokers. A shared
  // trigger gets one for each listed type its type clauses can match in its
  // region: the filter's type when it names one, a type prefix it requires,
  // and no type it excludes. The suffix comes from the type rather than its
  // position, so listing another type never renames an existing subscription.
  excluded_types = [for f in var.filter_not : f.value if f.key == "type"]
  extra_trigger_index = merge([
    for key, t in local.trigger_index : {
      for type, topics in var.extra_brokers :
      "${key}-x-${type}" => merge(t, {
        broker = topics[t.region]
        suffix = "-x${substr(sha256(type), 0, 4)}"
      })
      if(
        contains(keys(topics), t.region) &&
        lookup(t.filter, "type", type) == type &&
        startswith(type, lookup(t.prefix, "type", "")) &&
        !contains(local.excluded_types, type)
      )
    }
  ]...)

  // Shared triggers whose filter names a type in var.drop_shared_types. They
  // are removed only after extra_trigger_index is built from the full index,
  // so the dedicated triggers and every other key are unchanged.
  dropped_shared_triggers = {
    for key, t in local.trigger_index : key => t
    if contains(var.drop_shared_types, lookup(t.filter, "type", ""))
  }
  shared_trigger_index = {
    for key, t in local.trigger_index : key => t
    if !contains(keys(local.dropped_shared_triggers), key)
  }
}

// Create a subscription to the broker with filters for the specified event types
// We need a trigger for each region, each filter, and each prefix set
module "trigger" {
  for_each = merge(local.shared_trigger_index, local.extra_trigger_index)

  source = "chainguard-dev/common/infra//modules/cloudevent-trigger"

  project_id = var.project_id
  name       = "${var.name}-${each.value.region}-${each.value.index}${each.value.suffix}"
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

  team    = var.team
  product = var.product

  resource_manager_tags = var.resource_manager_tags

  depends_on = [module.subscriber]
  version    = "1.58.2"
}
