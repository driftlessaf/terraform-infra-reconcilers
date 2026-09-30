# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Run in CI by .github/workflows/tf-module-tests.yaml.
#
# Plan-only. Covers who holds what on the queue bucket, and by which resource
# shape. The shape is the point: a google_storage_bucket_iam_binding owns the
# whole member list for its role, so a binding on a role a consumer also grants
# would evict that consumer on apply and fight it on every plan thereafter.
# These assertions fail if the additive members are ever folded back into a
# binding.

mock_provider "google" {
  mock_data "google_project" {
    defaults = {
      number = "123456789"
    }
  }
}
mock_provider "google-beta" {}
mock_provider "null" {}
mock_provider "random" {
  mock_resource "random_string" {
    override_during = plan
    defaults = {
      result = "abc123"
    }
  }
}

variables {
  project_id = "fixture-project"
  name       = "fixture"
  regions = {
    "us-central1" = {
      network = "projects/fixture-project/global/networks/fixture"
      subnet  = "projects/fixture-project/regions/us-central1/subnetworks/fixture"
    }
  }
  concurrent-work = 1
  reconciler-service = {
    name = "fixture-reconciler"
  }
  team                  = "fixture"
  notification_channels = []
}

run "receiver_and_dispatcher_hold_object_user_additively" {
  command = plan

  assert {
    condition     = length(google_storage_bucket_iam_member.queue-writers) == 2
    error_message = "the receiver and dispatcher must each get their own member grant"
  }
  assert {
    condition = alltrue([
      for m in google_storage_bucket_iam_member.queue-writers : m.role == "roles/storage.objectUser"
    ])
    error_message = "queue writers must hold objectUser, not a broader role"
  }
}

# The binding these members replace is gone by default. It was retained for one
# release so the reduction could be taken and watched a deployment at a time,
# rather than reaching every caller on whichever apply ran first. That happened,
# so the default now carries the result and a caller that sets nothing takes the
# reduction on its next apply.
run "storage_admin_binding_is_absent_by_default" {
  command = plan

  assert {
    condition     = length(google_storage_bucket_iam_binding.global-authorize-access) == 0
    error_message = "the storage.admin binding must be gone by default; objectUser members replace it"
  }
}

# True is the escape hatch, for a caller whose objectUser grants have not been
# applied yet: the binding's destroy is not ordered after the members' create, so
# taking both in one apply leaves a brief window with no access. It has to keep
# working, and keep granting exactly what it granted before, or deferring is not
# actually available.
run "retaining_the_binding_restores_it_unchanged" {
  command = plan

  variables {
    retain_bucket_admin_binding = true
  }

  assert {
    condition     = google_storage_bucket_iam_binding.global-authorize-access[0].role == "roles/storage.admin"
    error_message = "retain_bucket_admin_binding = true must materialize the binding on its original role"
  }
  assert {
    condition     = length(google_storage_bucket_iam_member.queue-writers) == 2
    error_message = "retaining the binding must not disturb the additive objectUser grants"
  }
}

# A queue reader must not be swept into the write grants. This module grants
# three roles on one bucket -- objectUser, objectAdmin to dlq operators, and
# objectViewer to readers -- and all three are additive for the same reason.
run "queue_readers_do_not_enter_the_write_grants" {
  command = plan

  variables {
    queue_readers = ["serviceAccount:producer@fixture-project.iam.gserviceaccount.com"]
  }

  assert {
    condition     = length(google_storage_bucket_iam_member.queue-writers) == 2
    error_message = "a queue reader must not receive a write grant"
  }
  assert {
    condition = alltrue([
      for m in google_storage_bucket_iam_member.queue-readers : m.role == "roles/storage.objectViewer"
    ])
    error_message = "queue readers must hold objectViewer on their own additive grants"
  }
}

# Flipping the gate is the only step that revokes anything, and it must revoke
# only that binding: the additive grants the identities depend on afterwards
# have to survive it.
run "dropping_the_admin_binding_leaves_the_object_user_grants" {
  command = plan

  variables {
    retain_bucket_admin_binding = false
  }

  assert {
    condition     = length(google_storage_bucket_iam_binding.global-authorize-access) == 0
    error_message = "retain_bucket_admin_binding = false must remove the storage.admin binding"
  }
  assert {
    condition     = length(google_storage_bucket_iam_member.queue-writers) == 2
    error_message = "the receiver and dispatcher must keep their grants once the binding is gone"
  }
  assert {
    condition = alltrue([
      for m in google_storage_bucket_iam_member.queue-writers : m.role == "roles/storage.objectUser"
    ])
    error_message = "the surviving grants must be objectUser"
  }
}
