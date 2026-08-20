output "service" {
  value       = google_cloud_run_v2_service.service
  description = "The service."
}

output "backend_service" {
  value       = var.create_backend_service ? google_compute_backend_service.backend_service[0] : null
  description = "The backend service, if one was created."
}

output "domain_names" {
  value       = var.domain_names
  description = "The domain name of the service."
}

// NOTE: If IAM is to be applied, it needs to be done before the service is created; in that case, use
//  the `existing_service_account_email` input variable.

output "service_account" {
  value       = var.existing_service_account_email == "" ? google_service_account.service_account[0] : null
  description = "The service account, if one was created."
}