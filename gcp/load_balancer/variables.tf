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