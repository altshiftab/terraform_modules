variable "name_prefix" {
    type        = string
    description = "The name prefix of the secret."
}

variable "project_id" {
    type        = string
    description = "GCP project identifier"
}

variable "secret_data" {
    type = string
    description = "The secret data."
    sensitive = true
}

variable "accessor_emails" {
    type        = list(string)
    description = "A list of service account email addresses that should be granted access to the secret."
}
