// Copyright 2026 Chainguard, Inc.
// SPDX-License-Identifier: Apache-2.0

// The embeddings bucket is optional, so bind nothing when it is not created.
resource "google_tags_location_tag_binding" "embeddings_bucket" {
  for_each = var.create_gcs_bucket ? var.resource_manager_tags : {}

  parent    = "//storage.googleapis.com/projects/_/buckets/${google_storage_bucket.embeddings[0].name}"
  tag_value = each.value
  location  = lower(google_storage_bucket.embeddings[0].location)
}

// Vertex AI indexes and index endpoints have no tag support. The bucket above
// is the only resource this input reaches, and it is not the module's main cost.
