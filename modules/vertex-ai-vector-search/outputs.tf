/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

output "index_id" {
  description = "Fully-qualified resource name of the Vertex AI index."
  value       = google_vertex_ai_index.this.id
}

output "index_endpoint_id" {
  description = "Fully-qualified resource name of the index endpoint."
  value       = google_vertex_ai_index_endpoint.this.id
}

output "deployed_index_id" {
  description = "ID of the deployed index within the endpoint."
  value       = google_vertex_ai_index_endpoint_deployed_index.this.deployed_index_id
}

output "public_endpoint_domain_name" {
  description = "Public domain name for gRPC queries to the deployed index."
  value       = google_vertex_ai_index_endpoint.this.public_endpoint_domain_name
}

output "gcs_bucket_name" {
  description = "Name of the GCS bucket for embedding storage. Empty if create_gcs_bucket is false."
  value       = var.create_gcs_bucket ? google_storage_bucket.embeddings[0].name : ""
}
