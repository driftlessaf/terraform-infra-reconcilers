// Copyright 2026 Chainguard, Inc.
// SPDX-License-Identifier: Apache-2.0

// The binding parent needs the numeric project number. Read only when tags are set.
data "google_project" "resource_manager_tags" {
  count = length(var.resource_manager_tags) > 0 ? 1 : 0

  project_id = local.project_id
}

locals {
  workqueue_topic_tag_bindings = {
    for pair in setproduct(keys(google_pubsub_topic.global-object-change-notifications), keys(var.resource_manager_tags)) :
    "${pair[0]}/${pair[1]}" => {
      name      = google_pubsub_topic.global-object-change-notifications[pair[0]].name
      tag_value = var.resource_manager_tags[pair[1]]
    }
  }

  workqueue_subscription_tag_bindings = {
    for pair in setproduct(keys(google_pubsub_subscription.global-this), keys(var.resource_manager_tags)) :
    "${pair[0]}/${pair[1]}" => {
      name      = google_pubsub_subscription.global-this[pair[0]].name
      tag_value = var.resource_manager_tags[pair[1]]
    }
  }
}

// The workqueue bucket is only created when the workqueue is enabled.
resource "google_tags_location_tag_binding" "global_workqueue_bucket" {
  for_each = local.workqueue_enabled ? var.resource_manager_tags : {}

  parent    = "//storage.googleapis.com/projects/_/buckets/${google_storage_bucket.global-workqueue[0].name}"
  tag_value = each.value
  location  = lower(google_storage_bucket.global-workqueue[0].location)
}

// Pub/Sub bindings are global.
resource "google_tags_tag_binding" "global_object_change_topic" {
  for_each = local.workqueue_topic_tag_bindings

  parent    = "//pubsub.googleapis.com/projects/${data.google_project.resource_manager_tags[0].number}/topics/${each.value.name}"
  tag_value = each.value.tag_value
}

resource "google_tags_tag_binding" "global_subscription" {
  for_each = local.workqueue_subscription_tag_bindings

  parent    = "//pubsub.googleapis.com/projects/${data.google_project.resource_manager_tags[0].number}/subscriptions/${each.value.name}"
  tag_value = each.value.tag_value
}

// google_cloud_scheduler_job (dispatcher.tf) has no Resource Manager tag support
// in the provider, so the dispatcher's scheduler trigger stays unattributed at
// resource level. Its cost is negligible next to the Cloud Run services, which
// are tagged via the forwarded regional-go-service modules.
