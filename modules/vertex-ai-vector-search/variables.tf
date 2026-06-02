/*
Copyright 2026 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

# ── Required ────────────────────────────────────────────────────────────

variable "name" {
  description = "Base name for all resources (index, endpoint, bucket). Lowercase letters, numbers, and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name))
    error_message = "name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region for the index and endpoint."
  type        = string
}

variable "team" {
  description = "Team label to apply to resources (replaces deprecated 'squad')."
  type        = string
}

# ── Vector Index ────────────────────────────────────────────────────────

variable "dimensions" {
  description = "Number of dimensions for embedding vectors. Must match the embedding model (e.g. 3072 for gemini-embedding-001, 768 for text-embedding-005)."
  type        = number

  validation {
    condition     = var.dimensions > 0
    error_message = "dimensions must be a positive integer."
  }
}

variable "description" {
  description = "Human-readable description for the index."
  type        = string
  default     = ""
}

variable "distance_measure_type" {
  description = "Distance measure for vector similarity. One of: COSINE_DISTANCE, SQUARED_L2_DISTANCE, L1_DISTANCE, DOT_PRODUCT_DISTANCE."
  type        = string
  default     = "COSINE_DISTANCE"

  validation {
    condition = contains([
      "COSINE_DISTANCE",
      "SQUARED_L2_DISTANCE",
      "L1_DISTANCE",
      "DOT_PRODUCT_DISTANCE",
    ], var.distance_measure_type)
    error_message = "distance_measure_type must be one of: COSINE_DISTANCE, SQUARED_L2_DISTANCE, L1_DISTANCE, DOT_PRODUCT_DISTANCE."
  }
}

variable "approximate_neighbors_count" {
  description = "Default number of approximate neighbors to return during search."
  type        = number
  default     = 150
}

variable "leaf_node_embedding_count" {
  description = "Number of embeddings per leaf node in the Tree-AH index. More embeddings per leaf = smaller index but slower search."
  type        = number
  default     = 1000
}

variable "leaf_nodes_to_search_percent" {
  description = "Percentage of leaf nodes to search (1-100). Higher = better recall, slower search."
  type        = number
  default     = 10

  validation {
    condition     = var.leaf_nodes_to_search_percent >= 1 && var.leaf_nodes_to_search_percent <= 100
    error_message = "leaf_nodes_to_search_percent must be between 1 and 100."
  }
}

variable "feature_norm_type" {
  description = "Feature normalization type. Use UNIT_L2_NORM with COSINE_DISTANCE for best results."
  type        = string
  default     = "UNIT_L2_NORM"

  validation {
    condition     = contains(["NONE", "UNIT_L2_NORM"], var.feature_norm_type)
    error_message = "feature_norm_type must be one of: NONE, UNIT_L2_NORM."
  }
}

# ── Endpoint & Deployment ───────────────────────────────────────────────

variable "machine_type" {
  description = "Machine type for serving the deployed index."
  type        = string
  default     = "e2-standard-16"
}

variable "min_replica_count" {
  description = "Minimum number of replicas for the deployed index."
  type        = number
  default     = 1
}

variable "max_replica_count" {
  description = "Maximum number of replicas for the deployed index."
  type        = number
  default     = 1
}

# ── GCS Bucket ──────────────────────────────────────────────────────────

variable "create_gcs_bucket" {
  description = "Create a GCS bucket for durable embedding storage. Set to false to bring your own bucket."
  type        = bool
  default     = true
}

variable "gcs_bucket_name" {
  description = "Name for the GCS bucket. Defaults to '{project}-{name}-embeddings' when create_gcs_bucket is true. When create_gcs_bucket is false, the caller is responsible for managing IAM on their own bucket."
  type        = string
  default     = ""
}

variable "gcs_lifecycle_age_days" {
  description = "Number of days before objects in the embeddings bucket are deleted. Set to 0 to disable lifecycle rules."
  type        = number
  default     = 0
}

# ── IAM ─────────────────────────────────────────────────────────────────

variable "authorized_service_accounts" {
  description = "List of Google service account emails to grant roles/aiplatform.user and GCS access."
  type        = list(string)
  default     = []
}

# ── Encryption ──────────────────────────────────────────────────────────

variable "encryption_key_name" {
  description = "Optional Cloud KMS key for CMEK encryption of the index, endpoint, and embeddings bucket; Google-managed encryption when null. The Vertex AI and GCS service agents must hold cryptoKeyEncrypterDecrypter on the key."
  type        = string
  default     = null
}

# ── Lifecycle ───────────────────────────────────────────────────────────

variable "deletion_protection" {
  description = "When true, prevents the GCS bucket from being destroyed with objects in it."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Additional labels to apply to resources."
  type        = map(string)
  default     = {}
}

variable "product" {
  description = "Product label to apply to resources."
  type        = string
  default     = "unknown"
}

# ── Operation timeouts ──────────────────────────────────────────────────

variable "index_timeouts" {
  description = "Timeouts for the Vertex AI index resource. Index creation can run well past the provider's default, so the defaults are generous; override any field as needed."
  type = object({
    create = optional(string, "2h")
    update = optional(string, "1h")
    delete = optional(string, "30m")
  })
  default = {}
}

variable "endpoint_timeouts" {
  description = "Timeouts for the Vertex AI index endpoint resource."
  type = object({
    create = optional(string, "1h")
    update = optional(string, "1h")
    delete = optional(string, "1h")
  })
  default = {}
}

variable "deployed_index_timeouts" {
  description = "Timeouts for deploying the index to the endpoint — the slowest operation, as it provisions dedicated serving machines."
  type = object({
    create = optional(string, "2h")
    update = optional(string, "1h")
    delete = optional(string, "1h")
  })
  default = {}
}
