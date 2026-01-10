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
