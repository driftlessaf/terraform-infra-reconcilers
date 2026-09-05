/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

module "push-listener" {
  source             = "chainguard-dev/common/infra//modules/regional-go-service"
  observability_role = var.observability_role

  name       = "${var.name}-push"
  project_id = var.project_id
  regions    = var.regions

  service_account = var.service_account

  containers = {
    push-listener = {
      source = {
        working_dir = path.module
        importpath  = "./cmd/push"
      }
      ports = [{
        container_port = 8080
      }]
      env = concat([{
        name  = "REPOS_CONFIG"
        value = jsonencode(var.repos)
        }, {
        name  = "OCTO_IDENTITY"
        value = var.octo_sts_identity
        }],
        var.github_app_id != 0 ? [{
          name  = "GITHUB_APP_ID"
          value = tostring(var.github_app_id)
          }, {
          name  = "GITHUB_APP_KEY"
          value = var.github_app_key
        }] : []
      )
      regional-env = [{
        name  = "WORKQUEUE_ADDR"
        value = { for region, auth in module.authorize-receiver-per-region : region => auth.uri }
      }]
    }
  }

  egress = "PRIVATE_RANGES_ONLY"

  deletion_protection   = var.deletion_protection
  notification_channels = var.notification_channels
  labels                = var.labels
  product               = var.product
  team                  = var.team
  resource_manager_tags = var.resource_manager_tags
  version               = "1.39.2"
}

locals {
  # Subscription map for push triggers.
  #
  # When var.repos is non-empty, create one trigger per (repo, region) pair
  # with a subject filter scoped to "owner/repo".
  #
  # When var.repos is empty (GitHub App installation mode — repos are
  # determined by where the app is installed), create one trigger per region
  # with no subject filter, so all pushes for every repo the app receives
  # webhooks for reach the handler. The handler discovers per-repo config by
  # fetching .{identity}.yaml at the pushed SHA. This mirrors the pattern in
  # cloudevents-prs in the github-metapathreconciler module.
  push_subscriptions = var.paused ? {} : (
    length(var.repos) > 0 ? {
      for pair in setproduct(keys(var.regions), var.repos) :
      "${pair[1].owner}/${pair[1].repo}/${pair[0]}" => {
        region  = pair[0]
        subject = "${pair[1].owner}/${pair[1].repo}"
      }
      } : {
      for region in keys(var.regions) :
      region => {
        region  = region
        subject = null
      }
    }
  )
}

# Subscribe to push events. Shape depends on whether var.repos is set; see
# local.push_subscriptions above.
module "push-subscription" {
  for_each = local.push_subscriptions

  source = "chainguard-dev/common/infra//modules/cloudevent-trigger"

  name   = "${var.name}-push"
  broker = var.broker[each.value.region]
  filter = each.value.subject == null ? {
    type = "dev.chainguard.github.push"
    } : {
    type    = "dev.chainguard.github.push"
    subject = each.value.subject
  }

  private-service = {
    region = each.value.region
    name   = "${var.name}-push"
  }

  project_id = var.project_id

  product = var.product
  team    = var.team

  notification_channels = var.notification_channels
  resource_manager_tags = var.resource_manager_tags

  depends_on = [module.push-listener]
  version    = "1.39.2"
}
