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

variable "ingress" {
  type        = string
  description = "Who may reach the service directly."
  default     = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  # The default blocks external requests to the `.run.app` address, so the load
  # balancer is the only way in and everything it does on the way past -- header
  # stripping, Cloud Armor, IAP -- cannot be walked around.
  #
  # Firebase Hosting cannot use that: it reaches the service over the public
  # run.app URL, so fronting a service with gcp/firebase_hosting means
  # "INGRESS_TRAFFIC_ALL" and accepting that the address answers to anyone the
  # service itself does not turn away.
  validation {
    condition = contains(
      ["INGRESS_TRAFFIC_ALL", "INGRESS_TRAFFIC_INTERNAL_ONLY", "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"],
      var.ingress,
    )
    error_message = "ingress must be one of INGRESS_TRAFFIC_ALL, INGRESS_TRAFFIC_INTERNAL_ONLY or INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER."
  }
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

variable "security_policy_id" {
  type        = string
  description = "Optional Cloud Armor security policy (self_link / id) to attach to the backend service. Leave null to skip."
  default     = null
}
variable "request_timeout_seconds" {
  type        = number
  description = "How long the service may take over a request before it is cut off. Applied to the service itself: a load balancer fronting a serverless NEG cannot be given a timeout, and refuses one rather than ignoring it. Null leaves the service's own default, which is this same 300 seconds."
  default     = 300

  validation {
    # Cloud Run's ceiling. Asked for more, the API refuses the whole service.
    condition     = var.request_timeout_seconds == null || (var.request_timeout_seconds > 0 && var.request_timeout_seconds <= 3600)
    error_message = "request_timeout_seconds must be between 1 and 3600, the longest a Cloud Run request may take."
  }
}
