output "ipv4_address" {
    value = google_compute_global_address.ipv4_address.address
    description = "The IPv4 address of the load balancer."
}

# Cloud DNS records an AAAA as eight groups: no :: standing in for a run of
# zeroes, and no leading zeroes within a group. The API hands the address back
# compressed, so writing it as it comes would differ from what is read back on
# the next plan, and go on differing.
#
# Terraform has no function that expands an address, and running one that does
# would make an interpreter a requirement of every machine and image this is ever
# planned on. The transform is short enough to do here instead.
#
# An IPv4-mapped address, whose last groups are written in dotted form, is not
# handled. A global forwarding rule is never given one.
locals {
    ipv6_halves = split("::", google_compute_global_address.ipv6_address.address)
    ipv6_head = local.ipv6_halves[0] == "" ? [] : split(":", local.ipv6_halves[0])

    ipv6_tail = (
        length(local.ipv6_halves) > 1 && local.ipv6_halves[1] != ""
        ? split(":", local.ipv6_halves[1])
        : []
    )

    ipv6_groups = (
        length(local.ipv6_halves) == 1
        ? local.ipv6_head
        : concat(
            local.ipv6_head,
            [for _ in range(8 - length(local.ipv6_head) - length(local.ipv6_tail)) : "0"],
            local.ipv6_tail,
        )
    )

    ipv6_address = join(":", [for group in local.ipv6_groups : format("%x", parseint(group, 16))])
}

output "ipv6_address" {
    value = local.ipv6_address
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
