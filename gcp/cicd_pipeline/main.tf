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
# by prefix. What is kept is decided by what is worth having rather than by what
# it costs: what the prefixes hold is a couple of gibibytes, at $0.023 a
# gibibyte-month.
resource "google_storage_bucket" "cicd" {
  project                     = var.project_id
  name                        = "${var.project_id}-cicd"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Every build overwrites the caches it reuses and writes a source archive that
  # the rules below later delete, and each of those deletions would otherwise be
  # retained -- and charged for -- a further seven days, that being the shortest
  # retention the policy allows short of none at all. Against a bucket written
  # once per build the copies so retained outweigh the live objects by an order
  # of magnitude, and not one of them is worth recovering: what a build reads is
  # reproducible from the commit that produced it.
  soft_delete_policy {
    retention_duration_seconds = 0
  }

  lifecycle_rule {
    condition {
      age            = var.cache_retention_days
      matches_prefix = ["cache/"]
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age            = var.source_retention_days
      matches_prefix = ["source/"]
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age            = var.report_retention_days
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


# Images.
#
# A Dockerfile is the repository's own code, and building one needs the network:
# base images are pulled and dependencies fetched. A build that runs that code
# must therefore hold nothing that can write. Cloud Build reaches the metadata
# server, so a poisoned dependency that runs during `go mod download` could take
# the build's own token and sign whatever image it liked — which is precisely
# what the attestation exists to prevent.
#
# So an image is built by one identity and published by another. What passes
# between them is a tarball in the bucket: opaque to the build that wrote it,
# and the only thing the publisher ever handles.
resource "google_service_account" "imager" {
  project      = var.project_id
  account_id   = "cicd-imager"
  display_name = "CI/CD image builder"
}

resource "google_project_iam_member" "imager_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.imager.email}"
}

# The bucket is where the source arrives and where the built tarball is left.
# Note that this is the identity's only write, and it reaches nothing outside
# the pipeline's own scratch space.
resource "google_storage_bucket_iam_member" "imager_bucket_object_admin" {
  bucket = google_storage_bucket.cicd.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.imager.email}"
}

# Nothing here grants the image build a secret. Fetching private modules while
# the image is built is done with a GitHub App installation token, minted per
# build by the service and staged in the bucket: it is scoped to the
# repositories the app is installed on and expires within the hour. A long-lived
# token in Secret Manager would put every private repository inside the blast
# radius of anything a Dockerfile runs.

resource "google_service_account_iam_member" "github_app_act_as_imager" {
  service_account_id = google_service_account.imager.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.github_app_service_account_email}"
}


# Publishing an image: loading the tarball, pushing it, signing the digest and
# recording the attestation that admits it. Nothing in this build runs anything
# the repository wrote, which is what lets it hold the signing key.
resource "google_service_account" "image_publisher" {
  project      = var.project_id
  account_id   = "cicd-image-publisher"
  display_name = "CI/CD image publisher"
}

resource "google_project_iam_member" "image_publisher_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.image_publisher.email}"
}

resource "google_storage_bucket_iam_member" "image_publisher_bucket_object_admin" {
  bucket = google_storage_bucket.cicd.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.image_publisher.email}"
}

resource "google_artifact_registry_repository_iam_member" "image_publisher_images_writer" {
  project    = var.project_id
  location   = var.images_repository_location
  repository = var.images_repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.image_publisher.email}"
}

# Signing. The key never leaves KMS: the publisher sends it a digest and reads
# back a signature, and holds no ability to read, export or destroy the key.
resource "google_kms_crypto_key_iam_member" "image_publisher_signer" {
  crypto_key_id = google_kms_crypto_key.image_signing.id
  role          = "roles/cloudkms.signerVerifier"
  member        = "serviceAccount:${google_service_account.image_publisher.email}"
}

# Recording the attestation takes two permissions in two places: attaching an
# occurrence to the note, and creating occurrences in the project they live in.
# Neither is implied by the other.
resource "google_container_analysis_note_iam_member" "image_publisher_attacher" {
  project = var.project_id
  note    = google_container_analysis_note.built_by_pipeline.name
  role    = "roles/containeranalysis.notes.attacher"
  member  = "serviceAccount:${google_service_account.image_publisher.email}"
}

resource "google_project_iam_member" "image_publisher_occurrence_editor" {
  project = var.project_id
  role    = "roles/containeranalysis.occurrences.editor"
  member  = "serviceAccount:${google_service_account.image_publisher.email}"
}

# The attestation names the public key it was made with, and the id the attestor
# matches against is the attestor's to state rather than the build's to guess.
# The build reads it instead of constructing it.
resource "google_binary_authorization_attestor_iam_member" "image_publisher_viewer" {
  project  = var.project_id
  attestor = google_binary_authorization_attestor.built_by_pipeline.name
  role     = "roles/binaryauthorization.attestorsViewer"
  member   = "serviceAccount:${google_service_account.image_publisher.email}"
}

resource "google_service_account_iam_member" "github_app_act_as_image_publisher" {
  service_account_id = google_service_account.image_publisher.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.github_app_service_account_email}"
}
