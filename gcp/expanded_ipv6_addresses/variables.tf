variable "addresses" {
    type = list(string)
    description = "IPv6 addresses to expand. Given in any form; returned in the one Cloud DNS records."
    default = []

    validation {
        condition = alltrue([for address in var.addresses : strcontains(address, ":")])
        error_message = "addresses must be IPv6 addresses. An address without a colon is not one."
    }

    validation {
        condition = alltrue([for address in var.addresses : !strcontains(address, ".")])
        error_message = "An IPv4-mapped address, whose last groups are written in dotted form, is not handled here. Nothing this serves is given one, and expanding it wrongly would be worse than refusing it."
    }
}
