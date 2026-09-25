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

# The binding these members replace. It is still here on purpose: dropping it in
# the same change that adds the members would put a revoke and a grant in one
# apply with no ordering between them. Removing it is a separate change, and
# this assertion is what that change has to update.
run "outgoing_storage_admin_binding_is_still_present" {
  command = plan

  assert {
    condition     = google_storage_bucket_iam_binding.global-authorize-access[0].role == "roles/storage.admin"
    error_message = "the outgoing binding must keep its original role until it is removed outright"
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
