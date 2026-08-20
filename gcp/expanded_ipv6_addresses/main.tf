# Cloud DNS records an IPv6 address as eight groups: no `::` standing in for a
# run of zeroes, and no leading zeroes within a group. An address written any
# other way differs from what is read back on the next plan, and goes on
# differing -- which is how a real change comes to be overlooked among records
# that always appear to be changing.
#
# Terraform has no function that expands an address, and running one that does
# would make an interpreter a requirement of every machine and image this is
# ever planned on. The transform is short enough to do here instead, and lives
# in one place because more than one caller needs it: a load balancer's own
# address, and the hints inside an HTTPS record.

locals {
    halves = { for address in var.addresses : address => split("::", address) }

    heads = {
        for address, halves in local.halves :
        address => halves[0] == "" ? [] : split(":", halves[0])
    }

    tails = {
        for address, halves in local.halves :
        address => length(halves) > 1 && halves[1] != "" ? split(":", halves[1]) : []
    }

    # An address with no `::` is already eight groups; one with it is the two
    # halves and however many zero groups are needed to make up the eight.
    groups = {
        for address, halves in local.halves :
        address => (
            length(halves) == 1
            ? local.heads[address]
            : concat(
                local.heads[address],
                [for _ in range(8 - length(local.heads[address]) - length(local.tails[address])) : "0"],
                local.tails[address],
            )
        )
    }
}
