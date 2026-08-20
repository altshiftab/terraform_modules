output "addresses" {
    value = {
        for address, groups in local.groups :
        address => join(":", [for group in groups : format("%x", parseint(group, 16))])
    }
    description = "Each address given, in the form Cloud DNS records it, keyed by the address as it was given."
}
