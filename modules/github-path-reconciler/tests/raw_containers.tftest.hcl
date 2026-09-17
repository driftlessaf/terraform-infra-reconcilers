# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

# Plan-only tests through the real child modules with mocked providers.
# Use terraform test -filter=tests/raw_containers.tftest.hcl -verbose to
# inspect the rendered child resources; native test assertions cannot
# access resources inside child modules.
mock_provider "ko" {}
mock_provider "cosign" {}
mock_provider "google" {
  mock_data "google_storage_project_service_account" {
    defaults = { email_address = "fixture-gcs@fixture-project.iam.gserviceaccount.com" }
  }
}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  project_id = "fixture-project"
  name       = "fixture"
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
  primary-region    = "us-central1"
  octo_sts_identity = "fixture"
  broker            = { "us-central1" = "fixture-broker" }
  repos = [{
    owner               = "fixture"
    repo                = "fixture"
    path_patterns       = [".*"]
    resync_period_hours = 1
  }]
}

run "omitted_short" {
  command = plan

  assert {
    condition     = length(var.raw_containers) == 0
    error_message = "Prebuilt containers must be opt-in."
  }
}

run "empty_short" {
  command = plan
  variables {
    raw_containers = {}
  }
}

run "omitted_long" {
  command = plan
  variables {
    mode = "long"
  }
}

run "empty_long" {
  command = plan
  variables {
    mode           = "long"
    raw_containers = {}
  }
}

run "prebuilt_sidecar" {
  command = plan
  variables {
    volumes = [{ name = "shared", empty_dir = {} }]
    raw_containers = {
      helper = {
        image = "example.com/helper@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        args  = ["--config=env:HELPER_CONFIG"]
        resources = {
          limits            = { cpu = "100m", memory = "128Mi" }
          startup_cpu_boost = false
        }
        env = [
          { name = "HELPER_CONFIG", value = "fixture-config" },
          { name = "TOKEN", value_source = { secret_key_ref = { secret = "fixture-secret", version = "1" } } },
        ]
        regional-env      = [{ name = "REGION_SETTING", value = { "us-central1" = "fixture-region" } }]
        regional-cpu-idle = { "us-central1" = false }
        volume_mounts     = [{ name = "shared", mount_path = "/shared" }]
      }
    }
  }
}

run "prebuilt_sidecar_rejected_in_long_mode" {
  command = plan
  variables {
    mode = "long"
    raw_containers = {
      helper = { image = "example.com/helper:fixture" }
    }
  }
  expect_failures = [var.raw_containers]
}
