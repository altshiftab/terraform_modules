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