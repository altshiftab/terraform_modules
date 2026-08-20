output "ipv4_address" {
    value = google_compute_global_address.ipv4_address.address
    description = "The IPv4 address of the load balancer."
}

# Expanded rather than passed on as it comes: the compute API hands the address
# back compressed and Cloud DNS records it as eight groups, so the two would
# differ on every plan. See gcp/expanded_ipv6_addresses for the whole of it.
output "ipv6_address" {
    value = module.expanded_ipv6_addresses.addresses[google_compute_global_address.ipv6_address.address]
    description = "The IPv6 address of the load balancer, in the form Cloud DNS records it."
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
