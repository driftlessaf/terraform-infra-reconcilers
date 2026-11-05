# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "ko" {}
mock_provider "cosign" {}
mock_provider "random" {}

override_resource {
  target          = module.reenqueue[0].module.impl.google_service_account.invoker
  override_during = plan
  values = {
    name   = "projects/fixture-project/serviceAccounts/scheduler@fixture-project.iam.gserviceaccount.com"
    email  = "scheduler@fixture-project.iam.gserviceaccount.com"
    member = "serviceAccount:scheduler@fixture-project.iam.gserviceaccount.com"
  }
}

variables {
  project_id = "fixture-project"
  name       = "fixture"
  regions = {
    us-central1 = {
      network = "projects/fixture-project/global/networks/fixture"
      subnet  = "projects/fixture-project/regions/us-central1/subnetworks/fixture"
    }
    us-east1 = {
      network = "projects/fixture-project/global/networks/fixture"
      subnet  = "projects/fixture-project/regions/us-east1/subnetworks/fixture"
    }
  }
  service_account       = "dispatcher@fixture-project.iam.gserviceaccount.com"
  notification_channels = []
  team                  = "fixture"
  receiver_ingress      = "INGRESS_TRAFFIC_ALL"
  reenqueue_invokers    = ["group:operators@example.com", "user:operator@example.com"]
  containers = {
    main = {
      source = {
        working_dir = "."
        importpath  = "example.com/fixture/cmd/recorder"
      }
      ports = [{ container_port = 8080 }]
    }
  }
}

run "short_mode_access_policy" {
  command = plan

  assert {
    condition = jsonencode(output.access_policy) == jsonencode({
      receiver = {
        for region in ["us-central1", "us-east1"] : region => {
          ingress        = "INGRESS_TRAFFIC_ALL"
          egress         = "ALL_TRAFFIC"
          connector      = null
          public_invoker = false
        }
      }
      dispatcher = {
        for region in ["us-central1", "us-east1"] : region => {
          project   = "fixture-project"
          location  = region
          name      = "fixture-rec"
          role      = "roles/run.invoker"
          member    = "serviceAccount:dispatcher@fixture-project.iam.gserviceaccount.com"
          condition = []
        }
      }
      reenqueue = {
        us-central1 = {
          project  = "fixture-project"
          location = "us-central1"
          name     = "fixture-wq-req-cron"
          role     = "roles/run.invoker"
          members = toset([
            "group:operators@example.com",
            "user:operator@example.com",
            "serviceAccount:scheduler@fixture-project.iam.gserviceaccount.com",
          ])
          condition = []
        }
      }
    })
    error_message = "The output must expose receiver IAM enforcement and the complete dispatcher and recovery invocation grants."
  }
}

run "long_mode_access_policy" {
  command = plan

  variables {
    mode               = "long"
    receiver_ingress   = "INGRESS_TRAFFIC_INTERNAL_ONLY"
    reenqueue_invokers = ["user:replacement@example.com"]
  }

  assert {
    condition = jsonencode(output.access_policy) == jsonencode({
      receiver = {
        for region in ["us-central1", "us-east1"] : region => {
          ingress        = "INGRESS_TRAFFIC_INTERNAL_ONLY"
          egress         = "ALL_TRAFFIC"
          connector      = null
          public_invoker = false
        }
      }
      dispatcher = {}
      reenqueue = {
        us-central1 = {
          project  = "fixture-project"
          location = "us-central1"
          name     = "fixture-wq-req-cron"
          role     = "roles/run.invoker"
          members = toset([
            "user:replacement@example.com",
            "serviceAccount:scheduler@fixture-project.iam.gserviceaccount.com",
          ])
          condition = []
        }
      }
    })
    error_message = "Long mode must expose no dispatcher-to-service grant and must preserve receiver ingress and replacement recovery invokers."
  }
}

run "sharded_access_policy_is_not_reported_as_inline" {
  command = plan

  variables {
    shards = 2
  }

  assert {
    condition     = output.access_policy == null
    error_message = "Sharded deployments must not report an access policy for an inline workqueue that does not exist."
  }
}
