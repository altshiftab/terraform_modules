output "ipv4_address" {
    value = google_compute_global_address.ipv4_address.address
    description = "The IPv4 address of the load balancer."
}

module "expand_example" {
    source = "./expand_ipv6"
    ipv6 = google_compute_global_address.ipv6_address.address
}

output "ipv6_address" {
    value = module.expand_example.expanded
    description = "The IPv6 address of the load balancer."
}

output "dns_authorizations" {
    description = "DNS records the caller must publish so Certificate Manager can issue DV certs."
    value = {
        for domain, auth in google_certificate_manager_dns_authorization.auth :
        domain => {
            name = auth.dns_resource_record[0].name
            type = auth.dns_resource_record[0].type
            data = auth.dns_resource_record[0].data
        }
    }
}
