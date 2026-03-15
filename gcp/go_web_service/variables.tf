variable "name" {
  type        = string
  description = "The name of the service."
}

variable "project_id" {
  type        = string
  description = "GCP project identifier"
}

variable "region" {
  type        = string
  description = "The GCP region."
}

variable "image_url" {
  type        = string
  description = "The URL of the image."
}

variable "domain_names" {
  type        = list(string)
  description = "The domains names of the service."
}

variable "environment_variables" {
  type        = map(string)
  description = "Environment variables."
  default     = {}
}

variable "secret_environment_variables" {
  type        = map(string)
  description = "Secret environment variables."
  default     = {}
}

variable "public" {
  type        = bool
  description = "Whether the service is publicly accessible. If false, IAP is enabled."
  default     = false
}

variable "members" {
  type        = list(string)
  description = "The members with access to the service. Only used when public is false."
  default     = []
}

variable "iap_oauth_client_id" {
  type    = string
  default = ""
}

variable "iap_oauth_client_secret" {
  type    = string
  default = ""
}

variable "use_http2" {
  type    = bool
  default = true
}

variable "execution_environment" {
  type    = string
  default = null
}

variable "existing_service_account_email" {
  type    = string
  default = ""
}

variable "network_interfaces" {
  type = list(object({
    network    = string
    subnetwork = string
  }))
  default = []
}

variable "cloud_sql_connections" {
  type        = list(string)
  description = "List of Cloud SQL instance connection names to connect to."
  default     = []
}

variable "firewall_config" {
  type = object(
    {
      project_id             = string
      network_id             = string
      subnetwork_range       = string
      firewall_policy        = string
      fqdns                  = list(string)
      priority               = number
      name                   = optional(string)
      subnetwork_iam_members = optional(list(string), [])
    }
  )
  default = null
}