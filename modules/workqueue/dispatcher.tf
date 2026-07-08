// Compute a suffix that satisfies the regex:
// ^[a-z](?:[-a-z0-9]{4,28}[a-z0-9])$
resource "random_string" "dispatcher" {
  length  = 30 - length(local.sa_prefix)
  special = false
  upper   = false
}

// Create a dedicated GSA for the dispatcher service.
resource "google_service_account" "dispatcher" {
  project = local.project_id

  account_id   = "${local.sa_prefix}${random_string.dispatcher.result}"
  display_name = "Workqueue Dispatcher"
  description  = "The identity as which the workqueue dispatcher service runs for the ${local.name} workqueue."
}

// Authorize the dispatcher service account to call the target.
module "dispatcher-calls-target" {
  for_each = local.dispatcher_calls_target_enabled ? local.regions : {}

  source = "chainguard-dev/common/infra//modules/authorize-private-service"

  project_id = local.project_id
  region     = each.key
  name       = local.reconciler_service_name

  service-account = local.dispatcher_sa_email
  version         = "1.12.1"
}

// Authorize the dispatcher service account to call the error event broker.
module "dispatcher-calls-error-broker" {
  for_each = local.error_event_ingress != null ? local.regions : {}

  source = "chainguard-dev/common/infra//modules/authorize-private-service"

  project_id = local.project_id
  region     = each.key
  name       = local.error_event_ingress.name

  service-account = local.dispatcher_sa_email
  version         = "1.12.1"
}

// Compute a suffix that satisfies the regex:
// ^[a-z](?:[-a-z0-9]{4,28}[a-z0-9])$
resource "random_string" "cron-trigger" {
  length  = 30 - length(local.sa_prefix)
  special = false
  upper   = false
}

// Create a dedicated GSA for the cron trigger.
resource "google_service_account" "cron-trigger" {
  project = local.project_id

  account_id   = "${local.sa_prefix}${random_string.cron-trigger.result}"
  display_name = "Workqueue Cron Trigger"
  description  = "The identity as which the cloud scheduler will invoke the ${local.name} dispatcher."
}

// Authorize the cron-trigger service account to call the dispatcher service.
// Only used in short mode; long mode IAM is managed by the job resources.
module "cron-trigger-calls-dispatcher" {
  for_each = local.dispatcher_cron_enabled ? local.regions : {}

  source = "chainguard-dev/common/infra//modules/authorize-private-service"

  project_id = local.project_id
  region     = each.key
  name       = local.dispatcher_service_name

  service-account = google_service_account.cron-trigger.email

  // The binding only references the service name as a string, so without this
  // Terraform schedules the IAM call in parallel with the Cloud Run service
  // create and races on first apply.
  depends_on = [module.dispatcher-service]
  version    = "1.12.1"
}

resource "google_cloud_scheduler_job" "cron" {
  for_each = local.dispatcher_cron_enabled ? local.regions : {}

  name        = "${local.name}-${each.key}"
  description = "Periodically trigger the dispatcher to dispatch work."
  // Schedule this to run every minute.  We do this more frequently now
  // because otherwise we risk delaying tasks with a NotBefore for up to 30m
  // if the workqueue is otherwise idle.
  schedule         = "* * * * *"
  time_zone        = "America/New_York"
  attempt_deadline = "1800s" // The maximum
  region           = each.key

  http_target {
    http_method = "GET"
    uri         = module.cron-trigger-calls-dispatcher[each.key].uri

    oidc_token {
      service_account_email = google_service_account.cron-trigger.email
      // There is a provider bug, so despite this being the default, we provide it explicitly.
      audience = module.cron-trigger-calls-dispatcher[each.key].uri
    }
  }
}

// The change-trigger resources below deliver GCS object-change notifications
// directly to the dispatcher, enabling low-latency dispatch when new keys are
// enqueued.  They are disabled in long mode because the job-based dispatcher
// is driven exclusively by the per-minute cron.

// Compute a suffix that satisfies the regex:
// ^[a-z](?:[-a-z0-9]{4,28}[a-z0-9])$
resource "random_string" "change-trigger" {
  count   = local.dispatcher_change_trigger_enabled ? 1 : 0
  length  = 30 - length(local.sa_prefix)
  special = false
  upper   = false
}

// Create a dedicated GSA for the object change notification subscription.
resource "google_service_account" "change-trigger" {
  count   = local.dispatcher_change_trigger_enabled ? 1 : 0
  project = local.project_id

  account_id   = "${local.sa_prefix}${random_string.change-trigger[0].result}"
  display_name = "Workqueue Change Trigger"
  description  = "The identity as which the pubsub object change subscription will invoke the ${local.name} dispatcher."
}

// Lookup the identity of the pubsub service agent.
resource "google_project_service_identity" "pubsub" {
  count    = local.dispatcher_change_trigger_enabled ? 1 : 0
  provider = google-beta
  project  = local.project_id
  service  = "pubsub.googleapis.com"
}

// Authorize Pub/Sub to impersonate the delivery service account to authorize
// deliveries using this service account.
// NOTE: we use binding vs. member because we expect nothing but pubsub to be
// able to assume this identity.
resource "google_service_account_iam_binding" "allow-pubsub-to-mint-tokens" {
  count              = local.dispatcher_change_trigger_enabled ? 1 : 0
  service_account_id = google_service_account.change-trigger[0].name

  role    = "roles/iam.serviceAccountTokenCreator"
  members = ["serviceAccount:${google_project_service_identity.pubsub[0].email}"]
}

// Authorize the change-trigger service account to call the dispatcher.
module "change-trigger-calls-dispatcher" {
  for_each = local.dispatcher_change_trigger_enabled ? local.regions : {}

  source = "chainguard-dev/common/infra//modules/authorize-private-service"

  project_id = local.project_id
  region     = each.key
  name       = local.dispatcher_service_name

  service-account = google_service_account.change-trigger[0].email

  // See cron-trigger-calls-dispatcher above — same race.
  depends_on = [module.dispatcher-service]
  version    = "1.12.1"
}

resource "google_pubsub_subscription" "global-this" {
  for_each = local.dispatcher_change_trigger_enabled ? local.regions : {}

  // Ensure Pub/Sub can mint OIDC tokens for the change-trigger SA before
  // creating the push subscription that depends on it.
  depends_on = [google_service_account_iam_binding.allow-pubsub-to-mint-tokens]

  name   = "${local.name}-global-${each.key}"
  topic  = google_pubsub_topic.global-object-change-notifications[each.key].id
  labels = merge({ "service" : local.reconciler_service_name }, local.merged_labels)

  ack_deadline_seconds = 600 // Maximum value

  push_config {
    push_endpoint = module.change-trigger-calls-dispatcher[each.key].uri

    // Authenticate requests to this service using tokens minted
    // from the given service account.
    oidc_token {
      service_account_email = google_service_account.change-trigger[0].email
    }
  }

  expiration_policy {
    ttl = "" // This does not expire.
  }
}
