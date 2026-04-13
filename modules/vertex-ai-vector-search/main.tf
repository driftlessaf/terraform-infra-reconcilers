/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

# ── Labels ──────────────────────────────────────────────────────────────

locals {
  default_labels = {
    basename(abspath(path.module)) = var.name
    terraform-module               = basename(abspath(path.module))
  }
  squad_label = {
    squad = var.team
    team  = var.team
  }
  product_label = var.product != "" ? {
    product = var.product
  } : {}
  merged_labels = merge(local.default_labels, local.squad_label, local.product_label, var.labels)

  gcs_bucket_name = var.gcs_bucket_name != "" ? var.gcs_bucket_name : "${var.project}-${var.name}-embeddings"
}

# ── GCS bucket for durable embedding storage ────────────────────────────

resource "google_storage_bucket" "embeddings" {
  count = var.create_gcs_bucket ? 1 : 0

  project                     = var.project
  name                        = local.gcs_bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = !var.deletion_protection
  labels                      = local.merged_labels

  dynamic "lifecycle_rule" {
    for_each = var.gcs_lifecycle_age_days > 0 ? [1] : []
    content {
      action {
        type = "Delete"
      }
      condition {
        age = var.gcs_lifecycle_age_days
      }
    }
  }
}

# ── Vertex AI Matching Engine Index ─────────────────────────────────────

resource "google_vertex_ai_index" "this" {
  project      = var.project
  region       = var.region
  display_name = var.name
  description  = var.description
  labels       = local.merged_labels

  metadata {
    config {
      dimensions                  = var.dimensions
      approximate_neighbors_count = var.approximate_neighbors_count
      distance_measure_type       = var.distance_measure_type
      feature_norm_type           = var.feature_norm_type

      algorithm_config {
        tree_ah_config {
          leaf_node_embedding_count    = var.leaf_node_embedding_count
          leaf_nodes_to_search_percent = var.leaf_nodes_to_search_percent
        }
      }
    }
  }

  index_update_method = "STREAM_UPDATE"
}

# ── Index Endpoint ──────────────────────────────────────────────────────

resource "google_vertex_ai_index_endpoint" "this" {
  project      = var.project
  region       = var.region
  display_name = "${var.name}-endpoint"
  description  = "Vector search endpoint for ${var.name}"
  labels       = local.merged_labels
}

# ── Deploy Index to Endpoint ────────────────────────────────────────────

resource "google_vertex_ai_index_endpoint_deployed_index" "this" {
  index_endpoint    = google_vertex_ai_index_endpoint.this.id
  index             = google_vertex_ai_index.this.id
  deployed_index_id = replace(var.name, "-", "_")
  display_name      = var.name

  dedicated_resources {
    machine_spec {
      machine_type = var.machine_type
    }
    min_replica_count = var.min_replica_count
    max_replica_count = var.max_replica_count
  }
}

# ── IAM ─────────────────────────────────────────────────────────────────

resource "google_project_iam_member" "aiplatform_user" {
  for_each = toset(var.authorized_service_accounts)

  project = var.project
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${each.value}"
}

resource "google_storage_bucket_iam_member" "gcs_writer" {
  for_each = var.create_gcs_bucket ? toset(var.authorized_service_accounts) : toset([])

  bucket = google_storage_bucket.embeddings[0].name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${each.value}"
}
