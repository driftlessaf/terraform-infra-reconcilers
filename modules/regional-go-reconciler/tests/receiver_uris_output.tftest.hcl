# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

mock_provider "ko" {}
mock_provider "cosign" {}
mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  project_id = "fixture-project"
  name       = "fixture"
  mode       = "short"
  regions = {
    "us-central1" = {
      network = "projects/fixture-project/global/networks/fixture"
      subnet  = "projects/fixture-project/regions/us-central1/subnetworks/fixture"
    }
  }
  service_account       = "fixture@fixture-project.iam.gserviceaccount.com"
  notification_channels = []
  team                  = "fixture"
  containers = {
    "main" = {
      source = {
        working_dir = "."
        importpath  = "example.com/fixture/cmd/app"
      }
      ports = [{ container_port = 8080 }]
    }
  }
}

run "receiver_uris_by_region" {
  command = plan

  override_resource {
    target          = module.receiver-service[0].module.this.google_cloud_run_v2_service.this["us-central1"]
    override_during = plan
    values = {
      uri = "https://fixture-rcv.run.app"
    }
  }

  assert {
    condition     = output.receiver-uris == tomap({ "us-central1" = "https://fixture-rcv.run.app" })
    error_message = "the output must map each region to the workqueue receiver service's URI"
  }
}

run "sharded_receiver_uris_are_the_router" {
  command = plan

  variables {
    shards = 2
  }

  override_resource {
    target          = module.workqueue-sharded[0].module.hyperqueue-service.module.this.google_cloud_run_v2_service.this["us-central1"]
    override_during = plan
    values = {
      uri = "https://fixture-hq.run.app"
    }
  }

  assert {
    condition     = output.receiver-uris == tomap({ "us-central1" = "https://fixture-hq.run.app" })
    error_message = "a sharded reconciler accepts work at the hyperqueue router, so the output must map each region to the router's URI"
  }
}
