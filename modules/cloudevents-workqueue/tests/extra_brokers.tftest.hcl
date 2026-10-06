# Copyright 2026 Chainguard, Inc.
# SPDX-License-Identifier: Apache-2.0

# Plan-only tests through the real child modules with mocked providers.
mock_provider "ko" {}
mock_provider "cosign" {}
mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  project_id = "fixture-project"
  name       = "fixture-pr"
  regions = {
    "us-central1" = {
      network = "projects/fixture-project/global/networks/fixture"
      subnet  = "projects/fixture-project/regions/us-central1/subnetworks/fixture"
    }
    "us-east4" = {
      network = "projects/fixture-project/global/networks/fixture"
      subnet  = "projects/fixture-project/regions/us-east4/subnetworks/fixture"
    }
  }
  broker = {
    "us-central1" = "shared-us-central1"
    "us-east4"    = "shared-us-east4"
  }
  filters = [
    { subject = "org/repo", type = "dev.chainguard.github.pull_request" },
    { subject = "org/repo", type = "dev.chainguard.github.check_run", action = "completed" },
    { subject = "org/other" },
  ]
  filter_prefix         = { headbranch = "fixture/" }
  extension_key         = "pullrequesturl"
  workqueue             = { name = "fixture-rcv" }
  notification_channels = []
  team                  = "fixture"
}

run "no_extra_triggers_by_default" {
  command = plan

  assert {
    condition     = length(local.extra_trigger_index) == 0
    error_message = "parallel triggers must be opt-in"
  }

  assert {
    condition     = toset(keys(module.trigger)) == toset(["us-central1-0", "us-central1-1", "us-central1-2", "us-east4-0", "us-east4-1", "us-east4-2"])
    error_message = "the shared trigger keys must not change when extra_brokers is unset"
  }

  assert {
    condition     = alltrue([for t in values(local.trigger_index) : t.suffix == ""])
    error_message = "shared trigger names must not change when extra_brokers is unset"
  }
}

run "parallel_triggers_for_matching_filters" {
  command = plan

  variables {
    extra_brokers = {
      "dev.chainguard.github.check_run" = {
        "us-east4"    = "dedicated-check-run-us-east4"
        "europe-west" = "dedicated-check-run-europe-west"
      }
    }
  }

  # The check_run filter and the untyped filter can match check_run, so each
  # gets a parallel trigger in us-east4. The pull_request filter, us-central1
  # (no topic listed), and europe-west (not in var.regions) get none.
  assert {
    condition = toset(keys(local.extra_trigger_index)) == toset([
      "us-east4-1-x-dev.chainguard.github.check_run",
      "us-east4-2-x-dev.chainguard.github.check_run",
    ])
    error_message = "expected parallel triggers for the check_run and untyped filters in us-east4 only"
  }

  assert {
    condition = alltrue([
      for k, t in local.extra_trigger_index :
      t.broker == "dedicated-check-run-us-east4" && t.suffix == "-x0511"
    ])
    error_message = "parallel triggers must subscribe to the dedicated topic with the type-derived suffix"
  }

  assert {
    condition = alltrue([
      for k, t in local.extra_trigger_index :
      t.filter == local.trigger_index["${t.region}-${t.index}"].filter &&
      t.prefix == local.trigger_index["${t.region}-${t.index}"].prefix
    ])
    error_message = "a parallel trigger must reuse its shared trigger's filter and prefix"
  }

  assert {
    condition     = alltrue([for t in values(local.trigger_index) : startswith(t.broker, "shared-")])
    error_message = "shared triggers must stay on the shared broker"
  }

  assert {
    condition     = length(module.trigger) == 8
    error_message = "expected the six shared triggers plus two parallel triggers"
  }
}

run "listing_another_type_keeps_existing_names" {
  command = plan

  variables {
    extra_brokers = {
      "dev.chainguard.github.check_run" = {
        "us-east4" = "dedicated-check-run-us-east4"
      }
      "dev.chainguard.github.workflow_job" = {
        "us-east4" = "dedicated-workflow-job-us-east4"
      }
    }
  }

  # workflow_job matches only the untyped filter, and the check_run entries
  # keep the key and suffix they had with check_run listed alone.
  assert {
    condition = toset(keys(local.extra_trigger_index)) == toset([
      "us-east4-1-x-dev.chainguard.github.check_run",
      "us-east4-2-x-dev.chainguard.github.check_run",
      "us-east4-2-x-dev.chainguard.github.workflow_job",
    ])
    error_message = "unexpected parallel trigger set with two listed types"
  }

  assert {
    condition = (
      local.extra_trigger_index["us-east4-2-x-dev.chainguard.github.check_run"].suffix == "-x0511" &&
      local.extra_trigger_index["us-east4-2-x-dev.chainguard.github.workflow_job"].suffix == "-xa2db"
    )
    error_message = "suffixes must derive from the type, not its position"
  }
}

run "parallel_triggers_follow_each_prefix_set" {
  command = plan

  variables {
    filter_prefix = {}
    filter_prefixes = [
      { headbranch = "a/" },
      { headbranch = "b/" },
    ]
    filters = [
      { subject = "org/repo", type = "dev.chainguard.github.pull_request" },
      { subject = "org/repo", type = "dev.chainguard.github.check_run", action = "completed" },
    ]
    extra_brokers = {
      "dev.chainguard.github.check_run" = {
        "us-central1" = "dedicated-check-run-us-central1"
        "us-east4"    = "dedicated-check-run-us-east4"
      }
    }
  }

  assert {
    condition = toset(keys(local.extra_trigger_index)) == toset([
      "us-central1-1-x-dev.chainguard.github.check_run",
      "us-central1-3-x-dev.chainguard.github.check_run",
      "us-east4-1-x-dev.chainguard.github.check_run",
      "us-east4-3-x-dev.chainguard.github.check_run",
    ])
    error_message = "expected one parallel trigger per prefix set and region for the check_run filter"
  }

  assert {
    condition     = local.extra_trigger_index["us-central1-3-x-dev.chainguard.github.check_run"].prefix.headbranch == "b/"
    error_message = "a parallel trigger must carry its shared trigger's prefix set"
  }
}

run "no_parallel_trigger_for_excluded_types" {
  command = plan

  variables {
    filters = [
      { subject = "org/repo" },
    ]
    filter_prefix = {}
    filter_prefixes = [
      { type = "dev.chainguard.github.pull_request" },
      { type = "dev.chainguard.github.check" },
      {},
    ]
    filter_not = [
      { key = "type", value = "dev.chainguard.github.workflow_job" },
    ]
    extra_brokers = {
      "dev.chainguard.github.check_run" = {
        "us-east4" = "dedicated-check-run-us-east4"
      }
      "dev.chainguard.github.workflow_job" = {
        "us-east4" = "dedicated-workflow-job-us-east4"
      }
    }
  }

  # The untyped filter's pull_request prefix set can match neither listed type,
  # the check prefix set matches only check_run, and the unprefixed set would
  # match both but filter_not excludes workflow_job.
  assert {
    condition = toset(keys(local.extra_trigger_index)) == toset([
      "us-east4-1-x-dev.chainguard.github.check_run",
      "us-east4-2-x-dev.chainguard.github.check_run",
    ])
    error_message = "parallel triggers must respect type prefixes and type exclusions"
  }
}

run "dropping_nothing_keeps_every_trigger" {
  command = plan

  variables {
    extra_brokers = {
      "dev.chainguard.github.check_run" = {
        "us-central1" = "dedicated-check-run-us-central1"
        "us-east4"    = "dedicated-check-run-us-east4"
      }
    }
  }

  assert {
    condition     = length(local.dropped_shared_triggers) == 0 && local.shared_trigger_index == local.trigger_index
    error_message = "drop_shared_types must default to removing no shared trigger"
  }

  assert {
    condition     = toset(keys(module.trigger)) == toset(concat(keys(local.trigger_index), keys(local.extra_trigger_index)))
    error_message = "the trigger set must be unchanged when drop_shared_types is unset"
  }
}

run "dropping_check_run_removes_only_its_shared_triggers" {
  command = plan

  variables {
    extra_brokers = {
      "dev.chainguard.github.check_run" = {
        "us-central1" = "dedicated-check-run-us-central1"
        "us-east4"    = "dedicated-check-run-us-east4"
      }
    }
    # No filter names workflow_job, so listing it removes nothing: the untyped
    # filter keeps its shared trigger.
    drop_shared_types = [
      "dev.chainguard.github.check_run",
      "dev.chainguard.github.workflow_job",
    ]
  }

  assert {
    condition = toset(keys(module.trigger)) == toset([
      "us-central1-0",
      "us-central1-2",
      "us-east4-0",
      "us-east4-2",
      "us-central1-1-x-dev.chainguard.github.check_run",
      "us-central1-2-x-dev.chainguard.github.check_run",
      "us-east4-1-x-dev.chainguard.github.check_run",
      "us-east4-2-x-dev.chainguard.github.check_run",
    ])
    error_message = "only the shared check_run triggers must be removed; the dedicated and other shared triggers stay"
  }

  assert {
    condition = alltrue([
      for k, t in local.shared_trigger_index : t == local.trigger_index[k] && t.suffix == "" && startswith(t.broker, "shared-")
    ])
    error_message = "remaining shared triggers must keep their keys, names, and shared broker"
  }

  assert {
    condition = alltrue([
      for k, t in local.extra_trigger_index : startswith(t.broker, "dedicated-check-run-") && t.suffix == "-x0511"
    ])
    error_message = "dedicated triggers must keep their topic and type-derived suffix"
  }
}

run "dropping_a_type_without_a_topic_in_a_region_is_rejected" {
  command = plan

  variables {
    extra_brokers = {
      "dev.chainguard.github.check_run" = {
        "us-east4" = "dedicated-check-run-us-east4"
      }
    }
    drop_shared_types = ["dev.chainguard.github.check_run"]
  }

  expect_failures = [google_service_account.subscriber]
}
