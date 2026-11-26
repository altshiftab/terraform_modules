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
    description = <<-EOT
        The SSL policy's profile. FIPS_202205 is the one that refuses SHA-1 handshake signatures
        under TLS 1.2, at the cost of ChaCha20 and of plain X25519 key exchange (P-256, P-384 and
        X25519MLKEM768 remain), so a TLS 1.3 client sending only an X25519 key share pays a
        HelloRetryRequest. The minimum TLS version stays 1.2, which every profile here accepts.
    EOT

    validation {
        condition     = contains(["COMPATIBLE", "MODERN", "RESTRICTED", "FIPS_202205"], var.ssl_policy_profile)
        error_message = "ssl_policy_profile must be COMPATIBLE, MODERN, RESTRICTED or FIPS_202205 (CUSTOM needs features this module does not take)."
    }
}
