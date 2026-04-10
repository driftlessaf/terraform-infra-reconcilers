/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

module "push-listener" {
  source = "chainguard-dev/common/infra//modules/regional-go-service"

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
  version               = "1.0.3"
}

# Subscribe to push events for each (repo, region) pair
module "push-subscription" {
  for_each = var.paused ? {} : {
    for pair in setproduct(keys(var.regions), var.repos) :
    "${pair[1].owner}/${pair[1].repo}/${pair[0]}" => {
      region = pair[0]
      owner  = pair[1].owner
      repo   = pair[1].repo
    }
  }

  source = "chainguard-dev/common/infra//modules/cloudevent-trigger"

  name   = "${var.name}-push"
  broker = var.broker[each.value.region]
  filter = {
    type    = "dev.chainguard.github.push"
    subject = "${each.value.owner}/${each.value.repo}"
  }

  private-service = {
    region = each.value.region
    name   = "${var.name}-push"
  }

  project_id = var.project_id

  product = var.product
  team    = var.team

  notification_channels = var.notification_channels

  depends_on = [module.push-listener]
  version    = "1.0.3"
}
