data "google_project" "project" {
  project_id = var.project_id
}

locals {
  apis = concat(
    [
      "cloudbuild",
      "cloudkms",
      "binaryauthorization",
      "containeranalysis",
      "pubsub",
    ],
    var.enable_vulnerability_scanning ? ["containerscanning"] : [],
  )

  signing_key_version_id = "${google_kms_crypto_key.image_signing.id}/cryptoKeyVersions/1"
}

resource "google_project_service" "cicd" {
  for_each = toset(local.apis)

  project            = var.project_id
  service            = "${each.value}.googleapis.com"
  disable_on_destroy = false
}

# The identity builds run as, instead of any default Cloud Build service account.
resource "google_service_account" "builder" {
  project      = var.project_id
  account_id   = "cicd-builder"
  display_name = "CI/CD builder"
}

# Builds run with a user-specified service account, which requires an explicit
# log destination; the pipeline uses CLOUD_LOGGING_ONLY.
resource "google_project_iam_member" "builder_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.builder.email}"
}

resource "google_artifact_registry_repository_iam_member" "builder_images_writer" {
  project    = var.project_id
  location   = var.images_repository_location
  repository = var.images_repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.builder.email}"
}

# Build sources, Go build/test and lint caches, and test/lint reports, separated
# by prefix. Everything is reproducible or ephemeral, hence the deletion rules.
resource "google_storage_bucket" "cicd" {
  project                     = var.project_id
  name                        = "${var.project_id}-cicd"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  lifecycle_rule {
    condition {
      age            = 14
      matches_prefix = ["cache/"]
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age            = 30
      matches_prefix = ["source/"]
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age            = 90
      matches_prefix = ["report/"]
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket_iam_member" "builder_bucket_object_admin" {
  bucket = google_storage_bucket.cicd.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.builder.email}"
}

# Private npm packages are read from the registry with a token the build reads
# itself, so that it never passes through the orchestrating service.
data "google_secret_manager_secret" "npm_token" {
  count = var.npm_token_secret_id != "" ? 1 : 0

  project   = var.project_id
  secret_id = var.npm_token_secret_id
}

resource "google_secret_manager_secret_iam_member" "builder_npm_token" {
  count = var.npm_token_secret_id != "" ? 1 : 0

  project   = var.project_id
  secret_id = data.google_secret_manager_secret.npm_token[0].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.builder.email}"
}

# Image signing.

# NOTE: Key ring names are permanently reserved within a project and location;
# the key ring cannot be destroyed.
resource "google_kms_key_ring" "cicd" {
  project  = var.project_id
  name     = "cicd"
  location = var.region

  depends_on = [google_project_service.cicd["cloudkms"]]
}

resource "google_kms_crypto_key" "image_signing" {
  key_ring = google_kms_key_ring.cicd.id
  name     = "image-signing"
  purpose  = "ASYMMETRIC_SIGN"

  version_template {
    algorithm        = "EC_SIGN_P256_SHA256"
    protection_level = "SOFTWARE"
  }

  # Losing the key invalidates every existing signature and attestation.
  lifecycle {
    prevent_destroy = true
  }
}

data "google_kms_crypto_key_version" "image_signing" {
  crypto_key = google_kms_crypto_key.image_signing.id
}

# NOTE: The builder deliberately holds no signing or attestation rights. Builds
# execute code from the repositories they build, so a compromised dependency
# would inherit whatever the builder can do. Signing, attesting and deploying
# belong to a separate identity, driven by a build that only handles an image
# digest and never runs repository code.

# Binary Authorization.

resource "google_container_analysis_note" "built_by_pipeline" {
  project = var.project_id
  name    = "built-by-pipeline"

  attestation_authority {
    hint {
      human_readable_name = "Built by the CI/CD pipeline"
    }
  }

  depends_on = [google_project_service.cicd["containeranalysis"]]
}


resource "google_binary_authorization_attestor" "built_by_pipeline" {
  project = var.project_id
  name    = "built-by-pipeline"

  attestation_authority_note {
    note_reference = google_container_analysis_note.built_by_pipeline.id

    public_keys {
      # The id format `gcloud beta container binauthz attestations
      # sign-and-create --keyversion ...` matches attestations against.
      id = "//cloudkms.googleapis.com/v1/${local.signing_key_version_id}"

      pkix_public_key {
        public_key_pem      = data.google_kms_crypto_key_version.image_signing.public_key[0].pem
        signature_algorithm = "ECDSA_P256_SHA256"
      }
    }
  }

  depends_on = [google_project_service.cicd["binaryauthorization"]]
}


# The project-wide admission policy: Cloud Run only admits images attested by
# the pipeline. Google-maintained system images are exempted via the global
# policy.
resource "google_binary_authorization_policy" "policy" {
  project                       = var.project_id
  global_policy_evaluation_mode = "ENABLE"

  default_admission_rule {
    evaluation_mode         = "REQUIRE_ATTESTATION"
    enforcement_mode        = var.binary_authorization_enforcement_mode
    require_attestations_by = [google_binary_authorization_attestor.built_by_pipeline.id]
  }
}

# Releasing. Builds that run a repository's code must never hold credentials
# that can write, so publishing runs as an identity of its own: it only ever
# handles what a build already produced.
resource "google_service_account" "publisher" {
  project      = var.project_id
  account_id   = "cicd-publisher"
  display_name = "CI/CD publisher"
}

resource "google_project_iam_member" "publisher_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.publisher.email}"
}

resource "google_storage_bucket_iam_member" "publisher_bucket_object_admin" {
  bucket = google_storage_bucket.cicd.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.publisher.email}"
}

data "google_secret_manager_secret" "npm_publish_token" {
  count = var.npm_publish_token_secret_id != "" ? 1 : 0

  project   = var.project_id
  secret_id = var.npm_publish_token_secret_id
}

resource "google_secret_manager_secret_iam_member" "publisher_npm_publish_token" {
  count = var.npm_publish_token_secret_id != "" ? 1 : 0

  project   = var.project_id
  secret_id = data.google_secret_manager_secret.npm_publish_token[0].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.publisher.email}"
}

resource "google_service_account_iam_member" "github_app_act_as_publisher" {
  service_account_id = google_service_account.publisher.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.github_app_service_account_email}"
}

# Build events.

# Cloud Build publishes build state changes to this topic by virtue of its
# name; the topic existing is all that is needed.
resource "google_pubsub_topic" "cloud_builds" {
  project = var.project_id
  name    = "cloud-builds"

  depends_on = [google_project_service.cicd["pubsub"]]
}

# Work queued by webhook deliveries. GitHub gives a delivery ten seconds, which
# is not enough to stage a commit and start a build per unit, so the delivery
# only enqueues; failures are retried by the subscription.
resource "google_pubsub_topic" "work" {
  project = var.project_id
  name    = "cicd-work"

  depends_on = [google_project_service.cicd["pubsub"]]
}

resource "google_pubsub_topic_iam_member" "github_app_work_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.work.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${var.github_app_service_account_email}"
}

resource "google_pubsub_subscription" "work" {
  project = var.project_id
  name    = "cicd-work"
  topic   = google_pubsub_topic.work.id
  # Staging a commit and starting a build per unit takes longer than the
  # default deadline; redelivering while the work is in flight would duplicate
  # check runs.
  ack_deadline_seconds = 300

  push_config {
    push_endpoint = var.work_push_endpoint

    oidc_token {
      service_account_email = google_service_account.build_event_pusher.email
      audience              = var.work_push_endpoint
    }
  }

  retry_policy {
    minimum_backoff = "10s"
  }

  expiration_policy {
    ttl = ""
  }
}

resource "google_service_account" "build_event_pusher" {
  project      = var.project_id
  account_id   = "cicd-build-event-pusher"
  display_name = "CI/CD build event push identity"
}

# Pub/Sub mints OIDC tokens as the push identity through its service agent.
resource "google_service_account_iam_member" "pubsub_token_creator" {
  service_account_id = google_service_account.build_event_pusher.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription" "build_events" {
  project              = var.project_id
  name                 = "cicd-build-events"
  topic                = google_pubsub_topic.cloud_builds.id
  ack_deadline_seconds = 30

  push_config {
    push_endpoint = var.build_event_push_endpoint

    oidc_token {
      service_account_email = google_service_account.build_event_pusher.email
      audience              = var.build_event_push_endpoint
    }
  }

  retry_policy {
    minimum_backoff = "10s"
  }

  expiration_policy {
    ttl = ""
  }
}

# Deployment: the pipeline updates services to pipeline-built image digests.

resource "google_cloud_run_v2_service_iam_member" "builder_run_developer" {
  for_each = var.deployable_services

  project  = var.project_id
  location = var.region
  name     = each.key
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.builder.email}"
}

resource "google_service_account_iam_member" "builder_deploy_act_as" {
  for_each = var.deployable_services

  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value.service_account_email}"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.builder.email}"
}

# Orchestration: the GitHub App service creates builds that run as the builder
# service account, uploads build sources, and reads reports.

resource "google_project_iam_member" "github_app_builds_editor" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.editor"
  member  = "serviceAccount:${var.github_app_service_account_email}"

  depends_on = [google_project_service.cicd["cloudbuild"]]
}

resource "google_service_account_iam_member" "github_app_act_as_builder" {
  service_account_id = google_service_account.builder.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.github_app_service_account_email}"
}

resource "google_storage_bucket_iam_member" "github_app_bucket_object_admin" {
  bucket = google_storage_bucket.cicd.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.github_app_service_account_email}"
}
