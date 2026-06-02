# Vertex AI Vector Search Module

Provisions a Vertex AI Vector Search (Matching Engine) index with an endpoint
and deployed index, optionally with a GCS bucket for durable embedding storage.

Designed for RAG (Retrieval-Augmented Generation) workloads where teams need
to store and retrieve vector embeddings for semantic search.

For the Go client library that connects to the infrastructure this module provisions, see the [RAG library documentation](https://github.com/driftlessaf/go-driftlessaf/blob/main/agents/rag/RAG.md).

## Features

- Creates a Vertex AI Vector Search index with configurable dimensions, distance measure, and Tree-AH algorithm parameters
- Deploys the index to a public endpoint with configurable machine type and replica count
- Optionally creates a GCS bucket for durable embedding storage (dual-write for re-embedding on model upgrades)
- IAM bindings for authorized service accounts (`roles/aiplatform.user` + GCS access)
- Consistent labeling with team, product, and custom labels

## Usage example

```hcl
module "build_failures_index" {
  source = "github.com/chainguard-dev/terraform-infra-reconcilers//modules/vertex-ai-vector-search"

  name       = "build-failures"
  project    = "my-gcp-project"
  region     = "us-central1"
  team       = "eng-sus-tools"
  dimensions = 3072 # gemini-embedding-001

  authorized_service_accounts = [
    google_service_account.rag_mcp.email,
  ]
}

# Use outputs in your MCP server CORPORA_CONFIG:
# module.build_failures_index.index_id
# module.build_failures_index.deployed_index_id
# module.build_failures_index.public_endpoint_domain_name
```

## One index per corpus

Each embedding model produces vectors with a specific dimensionality (e.g.,
3072 for `gemini-embedding-001`, 768 for `text-embedding-005`). Since a
Matching Engine index is configured with fixed dimensions, **each corpus that
uses a different embedding model requires its own index**.

Call this module once per corpus:

```hcl
module "build_failures" {
  source     = "github.com/chainguard-dev/terraform-infra-reconcilers//modules/vertex-ai-vector-search"
  name       = "build-failures"
  dimensions = 3072 # gemini-embedding-001
  # ...
}

module "advisories" {
  source     = "github.com/chainguard-dev/terraform-infra-reconcilers//modules/vertex-ai-vector-search"
  name       = "advisories"
  dimensions = 768 # text-embedding-005
  # ...
}
```

If multiple corpora share the same model and dimensions, you can use a single
index with Vertex AI [restrict tokens](https://cloud.google.com/vertex-ai/docs/matching-engine/filtering)
to partition data by corpus at the application level.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 7.9.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | >= 7.9.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_project_iam_member.aiplatform_user](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_storage_bucket.embeddings](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_storage_bucket_iam_member.gcs_writer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [google_vertex_ai_index.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/vertex_ai_index) | resource |
| [google_vertex_ai_index_endpoint.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/vertex_ai_index_endpoint) | resource |
| [google_vertex_ai_index_endpoint_deployed_index.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/vertex_ai_index_endpoint_deployed_index) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_approximate_neighbors_count"></a> [approximate\_neighbors\_count](#input\_approximate\_neighbors\_count) | Default number of approximate neighbors to return during search. | `number` | `150` | no |
| <a name="input_authorized_service_accounts"></a> [authorized\_service\_accounts](#input\_authorized\_service\_accounts) | List of Google service account emails to grant roles/aiplatform.user and GCS access. | `list(string)` | `[]` | no |
| <a name="input_create_gcs_bucket"></a> [create\_gcs\_bucket](#input\_create\_gcs\_bucket) | Create a GCS bucket for durable embedding storage. Set to false to bring your own bucket. | `bool` | `true` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | When true, prevents the GCS bucket from being destroyed with objects in it. | `bool` | `true` | no |
| <a name="input_deployed_index_timeouts"></a> [deployed\_index\_timeouts](#input\_deployed\_index\_timeouts) | Timeouts for deploying the index to the endpoint — the slowest operation, as it provisions dedicated serving machines. | <pre>object({<br/>    create = optional(string, "2h")<br/>    update = optional(string, "1h")<br/>    delete = optional(string, "1h")<br/>  })</pre> | `{}` | no |
| <a name="input_description"></a> [description](#input\_description) | Human-readable description for the index. | `string` | `""` | no |
| <a name="input_dimensions"></a> [dimensions](#input\_dimensions) | Number of dimensions for embedding vectors. Must match the embedding model (e.g. 3072 for gemini-embedding-001, 768 for text-embedding-005). | `number` | n/a | yes |
| <a name="input_distance_measure_type"></a> [distance\_measure\_type](#input\_distance\_measure\_type) | Distance measure for vector similarity. One of: COSINE\_DISTANCE, SQUARED\_L2\_DISTANCE, L1\_DISTANCE, DOT\_PRODUCT\_DISTANCE. | `string` | `"COSINE_DISTANCE"` | no |
| <a name="input_encryption_key_name"></a> [encryption\_key\_name](#input\_encryption\_key\_name) | Optional Cloud KMS key for CMEK encryption of the index, endpoint, and embeddings bucket; Google-managed encryption when null. The Vertex AI and GCS service agents must hold cryptoKeyEncrypterDecrypter on the key. | `string` | `null` | no |
| <a name="input_endpoint_timeouts"></a> [endpoint\_timeouts](#input\_endpoint\_timeouts) | Timeouts for the Vertex AI index endpoint resource. | <pre>object({<br/>    create = optional(string, "1h")<br/>    update = optional(string, "1h")<br/>    delete = optional(string, "1h")<br/>  })</pre> | `{}` | no |
| <a name="input_feature_norm_type"></a> [feature\_norm\_type](#input\_feature\_norm\_type) | Feature normalization type. Use UNIT\_L2\_NORM with COSINE\_DISTANCE for best results. | `string` | `"UNIT_L2_NORM"` | no |
| <a name="input_gcs_bucket_name"></a> [gcs\_bucket\_name](#input\_gcs\_bucket\_name) | Name for the GCS bucket. Defaults to '{project}-{name}-embeddings' when create\_gcs\_bucket is true. When create\_gcs\_bucket is false, the caller is responsible for managing IAM on their own bucket. | `string` | `""` | no |
| <a name="input_gcs_lifecycle_age_days"></a> [gcs\_lifecycle\_age\_days](#input\_gcs\_lifecycle\_age\_days) | Number of days before objects in the embeddings bucket are deleted. Set to 0 to disable lifecycle rules. | `number` | `0` | no |
| <a name="input_index_timeouts"></a> [index\_timeouts](#input\_index\_timeouts) | Timeouts for the Vertex AI index resource. Index creation can run well past the provider's default, so the defaults are generous; override any field as needed. | <pre>object({<br/>    create = optional(string, "2h")<br/>    update = optional(string, "1h")<br/>    delete = optional(string, "30m")<br/>  })</pre> | `{}` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Additional labels to apply to resources. | `map(string)` | `{}` | no |
| <a name="input_leaf_node_embedding_count"></a> [leaf\_node\_embedding\_count](#input\_leaf\_node\_embedding\_count) | Number of embeddings per leaf node in the Tree-AH index. More embeddings per leaf = smaller index but slower search. | `number` | `1000` | no |
| <a name="input_leaf_nodes_to_search_percent"></a> [leaf\_nodes\_to\_search\_percent](#input\_leaf\_nodes\_to\_search\_percent) | Percentage of leaf nodes to search (1-100). Higher = better recall, slower search. | `number` | `10` | no |
| <a name="input_machine_type"></a> [machine\_type](#input\_machine\_type) | Machine type for serving the deployed index. | `string` | `"e2-standard-16"` | no |
| <a name="input_max_replica_count"></a> [max\_replica\_count](#input\_max\_replica\_count) | Maximum number of replicas for the deployed index. | `number` | `1` | no |
| <a name="input_min_replica_count"></a> [min\_replica\_count](#input\_min\_replica\_count) | Minimum number of replicas for the deployed index. | `number` | `1` | no |
| <a name="input_name"></a> [name](#input\_name) | Base name for all resources (index, endpoint, bucket). Lowercase letters, numbers, and hyphens. | `string` | n/a | yes |
| <a name="input_product"></a> [product](#input\_product) | Product label to apply to resources. | `string` | `"unknown"` | no |
| <a name="input_project"></a> [project](#input\_project) | GCP project ID. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | GCP region for the index and endpoint. | `string` | n/a | yes |
| <a name="input_team"></a> [team](#input\_team) | Team label to apply to resources (replaces deprecated 'squad'). | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_deployed_index_id"></a> [deployed\_index\_id](#output\_deployed\_index\_id) | ID of the deployed index within the endpoint. |
| <a name="output_gcs_bucket_name"></a> [gcs\_bucket\_name](#output\_gcs\_bucket\_name) | Name of the GCS bucket for embedding storage. Empty if create\_gcs\_bucket is false. |
| <a name="output_index_endpoint_id"></a> [index\_endpoint\_id](#output\_index\_endpoint\_id) | Fully-qualified resource name of the index endpoint. |
| <a name="output_index_id"></a> [index\_id](#output\_index\_id) | Fully-qualified resource name of the Vertex AI index. |
| <a name="output_public_endpoint_domain_name"></a> [public\_endpoint\_domain\_name](#output\_public\_endpoint\_domain\_name) | Public domain name for gRPC queries to the deployed index. |
<!-- END_TF_DOCS -->
