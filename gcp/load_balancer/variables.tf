variable "name" {
    type = string
    description = "The name of the load balancer."
}

variable "project_id" {
    type        = string
    description = "GCP project identifier"
}

variable "services" {
    type = list(
        object({
            domain_names = list(string)
            backend = string
        })
    )
    description = "Routing information for services."
}

variable "request_headers_to_remove" {
    type        = list(string)
    default     = []
    description = "Headers to remove from the request before sending it to the backend service."
}

variable "response_headers_to_remove" {
    type        = list(string)
    default     = ["Server", "Via", "traceparent", "X-Cloud-Trace-Context"]
    description = "Headers to remove from the response before sending it to the client."
}

variable "request_headers_to_add" {
    type = list(
        object({
            header_name  = string
            header_value = string
            replace      = bool
        })
    )
    default     = []
    description = "Custom request headers to add to all requests forwarded to backends."
}

variable "ssl_policy_profile" {
    type        = string
    default     = "RESTRICTED"
    description = "The SSL policy's profile; FIPS_202205 refuses SHA-1 handshake signatures under TLS 1.2, but drops ChaCha20 and plain X25519."

    validation {
        condition     = contains(["COMPATIBLE", "MODERN", "RESTRICTED", "FIPS_202205"], var.ssl_policy_profile)
        error_message = "ssl_policy_profile must be COMPATIBLE, MODERN, RESTRICTED or FIPS_202205 (CUSTOM needs features this module does not take)."
    }
}
