output "builder_service_account_email" {
  value       = google_service_account.builder.email
  description = "The email of the service account that builds run as."
}

output "build_event_pusher_service_account_email" {
  value       = google_service_account.build_event_pusher.email
  description = "The email of the identity that build event pushes authenticate as; the GitHub App service must require it in the push OIDC token."
}

output "bucket_name" {
  value       = google_storage_bucket.cicd.name
  description = "The name of the bucket holding build sources (source/), caches (cache/) and reports (report/)."
}

output "build_location" {
  # A bucket reports its location in uppercase, which is not a spelling Cloud
  # Build recognizes.
  value       = lower(google_storage_bucket.cicd.location)
  description = "The location builds must be created in. Builds read and write the bucket throughout — sources, caches and reports — and transfers between regions are both charged and slow, so builds belong in the bucket's region."
}

output "signing_key_version_id" {
  value       = local.signing_key_version_id
  description = "The KMS key version used for image signing and attestations, in projects/... form."
}

output "work_topic" {
  value       = google_pubsub_topic.work.name
  description = "The topic webhook deliveries enqueue build submissions on."
}

output "npm_token_secret_version_name" {
  value       = var.npm_token_secret_id != "" ? "${data.google_secret_manager_secret.npm_token[0].name}/versions/latest" : ""
  description = "The Secret Manager version resource name TypeScript unit builds read their registry token from; empty when no secret is configured."
}

output "attestor_id" {
  value       = google_binary_authorization_attestor.built_by_pipeline.id
  description = "The fully-qualified name of the Binary Authorization attestor."
}

output "publisher_service_account_email" {
  value       = google_service_account.publisher.email
  description = "The email of the service account publish builds run as."
}

output "npm_publish_token_secret_version_name" {
  value       = var.npm_publish_token_secret_id != "" ? "${data.google_secret_manager_secret.npm_publish_token[0].name}/versions/latest" : ""
  description = "The Secret Manager version resource name publish builds read their registry token from."
}

output "imager_service_account_email" {
  value       = google_service_account.imager.email
  description = "The email of the service account image builds run as. It can write nothing but the pipeline's own bucket, because it runs the repository's Dockerfile."
}

output "image_publisher_service_account_email" {
  value       = google_service_account.image_publisher.email
  description = "The email of the service account image publish builds run as. It pushes, signs and attests, and runs nothing the repository wrote."
}


output "images_repository" {
  value       = "${var.images_repository_location}-docker.pkg.dev/${var.project_id}/${var.images_repository_id}"
  description = "The registry prefix pipeline-built images are pushed under."
}

output "attestor_name" {
  value       = google_binary_authorization_attestor.built_by_pipeline.name
  description = "The short name of the Binary Authorization attestor, which publish builds read to learn the public key id their attestation must name."
}

output "note_name" {
  value       = google_container_analysis_note.built_by_pipeline.name
  description = "The short name of the Container Analysis note attestations are attached to."
}

output "terraform_plan_service_account_email" {
  value       = var.terraform_state_bucket != "" ? google_service_account.terraform_planner[0].email : ""
  description = "The email of the read-only identity Terraform plan builds run as. Empty when no state bucket was given, which is what makes a repository's Terraform unit report that this deployment cannot plan it."
}

output "terraform_registry_token_secret_version_name" {
  value       = var.terraform_registry_token_secret_id != "" ? "${data.google_secret_manager_secret.terraform_registry_token[0].id}/versions/latest" : ""
  description = "The Secret Manager version resource name of the private Terraform registry token, read by plan builds."
}
