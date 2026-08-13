variable "project_id" {
  type        = string
  description = "GCP project identifier"
}

variable "region" {
  type        = string
  description = "The GCP region."
}

variable "images_repository_location" {
  type        = string
  description = "The location of the Artifact Registry repository that pipeline-built images are pushed to."
}

variable "images_repository_id" {
  type        = string
  description = "The repository id of the Artifact Registry repository that pipeline-built images are pushed to."
}

variable "github_app_service_account_email" {
  type        = string
  description = "The service account email of the GitHub App service that orchestrates builds and receives build events."
}

variable "build_event_push_endpoint" {
  type        = string
  description = "The HTTPS URL on the GitHub App service that Cloud Build state changes are pushed to."
}

variable "deployable_services" {
  type        = map(object({ service_account_email = string }))
  description = "Cloud Run services the pipeline may deploy, keyed by service name, with each service's runtime service account email."
  default     = {}
}

variable "binary_authorization_enforcement_mode" {
  type        = string
  description = "The enforcement mode of the Binary Authorization policy. Keep the dry-run default until every service has been deployed through the pipeline once."
  default     = "DRYRUN_AUDIT_LOG_ONLY"

  validation {
    condition     = contains(["DRYRUN_AUDIT_LOG_ONLY", "ENFORCED_BLOCK_AND_AUDIT_LOG"], var.binary_authorization_enforcement_mode)
    error_message = "The enforcement mode must be DRYRUN_AUDIT_LOG_ONLY or ENFORCED_BLOCK_AND_AUDIT_LOG."
  }
}

variable "enable_vulnerability_scanning" {
  type        = bool
  description = "Whether to enable automatic vulnerability scanning of pushed images (billed per scanned image)."
  default     = true
}
