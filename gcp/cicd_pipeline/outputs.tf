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

output "signing_key_version_id" {
  value       = local.signing_key_version_id
  description = "The KMS key version used for image signing and attestations, in projects/... form."
}

output "npm_token_secret_version_name" {
  value       = var.npm_token_secret_id != "" ? "${data.google_secret_manager_secret.npm_token[0].name}/versions/latest" : ""
  description = "The Secret Manager version resource name TypeScript unit builds read their registry token from; empty when no secret is configured."
}

output "attestor_id" {
  value       = google_binary_authorization_attestor.built_by_pipeline.id
  description = "The fully-qualified name of the Binary Authorization attestor."
}
