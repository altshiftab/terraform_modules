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
