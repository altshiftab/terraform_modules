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

variable "work_push_endpoint" {
  type        = string
  description = "The HTTPS URL on the GitHub App service that queued build submissions are pushed to. Webhook deliveries must be acknowledged within seconds, so the work they cause is queued rather than done in the delivery."
}

variable "npm_token_secret_id" {
  type        = string
  description = "The secret id of a Secret Manager secret holding a registry token for private npm packages, read by TypeScript unit builds. Empty disables private package access."
  default     = ""
}

# Retention. What the bucket holds is small — a build's reports are tens of
# kilobytes, and caches are overwritten rather than accumulated — so these are
# set by what is worth keeping rather than by what it costs. Reports are the
# pipeline's only record of what a build did.
variable "cache_retention_days" {
  type        = number
  description = "How long a unit's cache is kept. A repository built less often than this rebuilds from nothing."
  default     = 90
}

variable "source_retention_days" {
  type        = number
  description = "How long the sources builds ran on are kept. Generated sources are not in the repository, so this is the only copy."
  default     = 90
}

variable "report_retention_days" {
  type        = number
  description = "How long build reports are kept. They hold the compile output and per-test timings a build was judged on."
  default     = 365
}

variable "enable_vulnerability_scanning" {
  type        = bool
  description = "Whether to enable automatic vulnerability scanning of pushed images (billed per scanned image)."
  default     = true
}

variable "npm_publish_token_secret_id" {
  type        = string
  description = "The secret id of a Secret Manager secret holding a registry token that may publish. Only the publisher reads it; empty disables publishing packages."
  default     = ""
}

variable "terraform_state_bucket" {
  type        = string
  description = "The bucket holding the Terraform state that plan builds read. Empty creates no planning identity, and a repository asking to be planned is told the deployment cannot."
  default     = ""
}

# A plan is not a report. It is applied, so it is only useful while the state it
# was made against has not moved, and it holds the resource attributes the
# configuration sets — secrets among them, in the same way the state does. Both
# of those argue for keeping it briefly: an approved plan that has gone stale
# should be planned again rather than found.
variable "plan_retention_days" {
  type        = number
  description = "How long a saved Terraform plan is kept. A pull request left open longer than this is planned again before it can be applied."
  default     = 30
}

variable "terraform_registry_token_secret_id" {
  type        = string
  description = "The secret id of a Secret Manager secret holding a token for a private Terraform provider registry, read by the plan build itself. Empty leaves the public registry, which needs no credentials."
  default     = ""
}

variable "terraform_plan_impersonated_service_accounts" {
  type        = set(string)
  description = "Service account emails a Terraform plan may mint tokens for, which a provider authenticating through domain-wide delegation needs. Name the read-only delegate here, never the writing one: a plan that can impersonate an identity inherits everything that identity may do."
  default     = []
}
