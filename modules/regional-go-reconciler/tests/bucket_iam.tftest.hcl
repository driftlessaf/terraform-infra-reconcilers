# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Run in CI by .github/workflows/tf-module-tests.yaml.
#
# Plan-only. bucket.tf is a symlink shared with the workqueue module, but this
# module is where the two cases that module cannot reach live: an inlined
# dispatcher that runs as the reconciler's own service account, and a sharded
# deployment that stands up no workqueue at all.
#
# Mock providers keep this fully offline: no credentials, no state.

mock_provider "ko" {}
mock_provider "cosign" {}
mock_provider "google" {}
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
}

# The inlined dispatcher runs as var.service_account, so that account needs the
# same object access the standalone dispatcher's own account gets -- and no
# more. Three grants: receiver, dispatcher, reconciler.
run "inlined_dispatcher_identity_gets_object_user" {
  command = plan

  assert {
    condition     = length(google_storage_bucket_iam_member.queue-writers) == 3
    error_message = "the reconciler service account must get a write grant alongside the receiver and dispatcher"
  }
  assert {
    condition = contains(
      google_storage_bucket_iam_member.queue-writers[*].member,
      "serviceAccount:fixture@fixture-project.iam.gserviceaccount.com",
    )
    error_message = "additional_bucket_members must reach the write grants"
  }
  assert {
    condition = alltrue([
      for m in google_storage_bucket_iam_member.queue-writers : m.role == "roles/storage.objectUser"
    ])
    error_message = "the inlined dispatcher must hold objectUser, not a broader role"
  }
}

# A dlq operator holds objectAdmin on the same bucket. Both grants are additive
# and neither owns the other's member list, which is the whole reason this is
# members rather than a binding.
run "dlq_operators_hold_a_separate_additive_role" {
  command = plan

  variables {
    dlq_operators = ["group:fixture-oncall@example.com"]
  }

  assert {
    condition     = length(google_storage_bucket_iam_member.queue-writers) == 3
    error_message = "a dlq operator must not enter the queue-writer grants"
  }
  assert {
    condition = alltrue([
      for m in google_storage_bucket_iam_member.dlq-operators : m.role == "roles/storage.objectAdmin"
    ])
    error_message = "dlq operators must keep objectAdmin on their own additive grants"
  }
}

# shards > 1 switches this module to hyperqueue and sets workqueue_enabled
# false, so the receiver and dispatcher accounts are never created. for_each is
# a meta-argument and is evaluated regardless, so it reads those accounts
# through [*] rather than [0]: an index would have to survive the unchosen
# branch of a conditional, and a splat needs no such guarantee.
run "sharded_deployment_grants_nothing_on_a_bucket_it_does_not_create" {
  command = plan

  variables {
    shards = 2

    # Not incidental to the case: hyperqueue's regional_concurrency_per_shard
    # check reads this even at its null default, and errors rather than
    # short-circuiting, so a sharded plan cannot be taken without it. That is a
    # defect in that check, unrelated to bucket IAM.
    regional-concurrent-work = 2
  }

  assert {
    condition     = length(google_storage_bucket_iam_member.queue-writers) == 0
    error_message = "a sharded deployment has no workqueue bucket, so it must plan no write grants"
  }
  assert {
    condition     = length(google_storage_bucket.global-workqueue) == 0
    error_message = "a sharded deployment must not create the standard workqueue bucket"
  }
}

# The inlined dispatcher runs as var.service_account, which is in the outgoing
# binding as well as the additive grants. Dropping the binding must not leave
# it short.
run "dropping_the_admin_binding_leaves_the_inlined_dispatcher_granted" {
  command = plan

  variables {
    retain_bucket_admin_binding = false
  }

  assert {
    condition     = length(google_storage_bucket_iam_binding.global-authorize-access) == 0
    error_message = "retain_bucket_admin_binding = false must remove the storage.admin binding"
  }
  assert {
    condition = contains(
      google_storage_bucket_iam_member.queue-writers[*].member,
      "serviceAccount:fixture@fixture-project.iam.gserviceaccount.com",
    )
    error_message = "the reconciler service account must keep a write grant once the binding is gone"
  }
}

# Sharded deployments get their buckets from workqueue/hyperqueue, which stands
# up one workqueue module per shard. The gate has to reach through both hops or
# it is unusable for exactly the deployments with the most buckets.
#
# The assertion is weaker than it should be: terraform test can only address
# resources in the configuration under test, so a nested shard's binding is out
# of reach and a dropped pass-through cannot be caught here. What this does
# catch is the variable going missing from hyperqueue or from the call, which
# fails the plan outright.
run "the_gate_reaches_the_sharded_path" {
  command = plan

  variables {
    shards                      = 2
    regional-concurrent-work    = 2
    retain_bucket_admin_binding = false
  }

  assert {
    condition     = length(google_storage_bucket_iam_binding.global-authorize-access) == 0
    error_message = "a sharded deployment has no inline binding to keep"
  }
}
