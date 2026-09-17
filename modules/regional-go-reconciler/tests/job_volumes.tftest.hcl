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
  mode       = "long"
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

run "job_defaults_carry_no_volumes" {
  command = plan

  assert {
    condition     = length(local.job_volumes) == 0
    error_message = "the long-mode job must not receive volumes when none are configured"
  }
}

run "job_receives_disk_empty_dir_and_skips_csi" {
  command = plan

  variables {
    launch_stage = "BETA"
    volumes = [
      {
        name      = "scratch"
        empty_dir = { medium = "DISK", size_limit = "10Gi" }
      },
      {
        name = "bucket"
        csi  = { driver = "gcsfuse.run.googleapis.com", volume_attributes = { bucketName = "fixture" } }
      },
    ]
  }

  assert {
    condition     = [for v in local.job_volumes : v.name] == ["scratch"]
    error_message = "the long-mode job must receive the empty_dir volume and skip csi entries"
  }

  assert {
    condition = alltrue([
      one(local.job_volumes).empty_dir.medium == "DISK",
      one(local.job_volumes).empty_dir.size_limit == "10Gi",
    ])
    error_message = "the DISK empty_dir medium and size_limit must reach the long-mode job"
  }
}

run "short_mode_projects_no_job_volumes" {
  command = plan

  variables {
    mode = "short"
    volumes = [{
      name      = "scratch"
      empty_dir = { medium = "DISK", size_limit = "10Gi" }
    }]
  }

  assert {
    condition     = length(local.job_volumes) == 0
    error_message = "short mode must not project job volumes"
  }
}
