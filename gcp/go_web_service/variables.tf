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

variable "vpc_connector" {
  type    = string
  default = null
}

variable "cloud_sql_connections" {
  type        = list(string)
  description = "List of Cloud SQL instance connection names to connect to."
  default     = []
}