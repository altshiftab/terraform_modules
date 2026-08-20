variable "name" {
    type = string
    description = "The name of the hosting configuration. Prefixes every site identifier."

    # A site id is "<name>-<16 hex digits>" and Firebase caps it at 30
    # characters, which leaves 13. Checked here because the alternative is an
    # apply that fails per site on a length nobody was counting.
    validation {
        condition = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name)) && length(var.name) <= 13
        error_message = "name must be a domain name label -- lowercase letters, digits and inner hyphens -- of at most 13 characters, because it is prefixed to a 17-character suffix to form a site id that Firebase caps at 30 and requires to be a valid hostname label."
    }
}

variable "project_id" {
    type        = string
    description = "GCP project identifier"
}

variable "services" {
    type = list(
        object({
            domain_names = list(string)
            service_name = string
            region       = string
        })
    )
    description = "Routing information for services. Mirrors the load balancer's variable of the same name, except that Firebase addresses a Cloud Run service by name and region rather than through a backend service."

    validation {
        # service_name keys the site, so two services sharing one would silently
        # collapse into a single site serving whichever won.
        condition = length(distinct([for s in var.services : s.service_name])) == length(var.services)
        error_message = "Every service must have a distinct service_name; it is what identifies the site."
    }

    validation {
        # Caught here rather than at apply, because the failure is otherwise a
        # 400 from the Hosting API naming neither the service nor the region.
        condition = alltrue([for s in var.services : contains(var.supported_regions, s.region)])
        error_message = "Firebase Hosting cannot rewrite to Cloud Run in ${join(", ", distinct([for s in var.services : s.region if !contains(var.supported_regions, s.region)]))}. Move the service to a supported region, or extend supported_regions if this list has fallen behind."
    }
}

variable "supported_regions" {
    type = list(string)
    description = "The Cloud Run regions Firebase Hosting can rewrite to. A snapshot of the documented list, overridable so that a region Google adds does not need a release of this module to be usable."

    # As documented on 2026-08-20. europe-north2 is deliberately absent: it is
    # not supported, while its neighbour europe-north1 is, which makes the
    # omission easy to read past.
    default = [
        "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
        "asia-south1", "asia-south2", "asia-southeast1", "asia-southeast2", "asia-southeast3",
        "australia-southeast1", "australia-southeast2", "europe-central2", "europe-north1",
        "europe-southwest1", "europe-west1", "europe-west12", "europe-west2", "europe-west3",
        "europe-west4", "europe-west6", "europe-west8", "europe-west9", "me-central1",
        "me-west1", "northamerica-northeast1", "northamerica-northeast2", "southamerica-east1",
        "southamerica-west1", "us-central1", "us-east1", "us-east4", "us-east5", "us-south1",
        "us-west1", "us-west2", "us-west3", "us-west4",
    ]
}

variable "create_firebase_project" {
    type = bool
    description = "Whether to add Firebase to the project. Adding it is a once-ever operation that fails with 409 if it has already happened, so set this false in a project that already has Firebase, or when a second instance of this module shares the project."
    default = true
}

variable "ip_addresses" {
    type = list(string)
    description = "The addresses a custom domain's A records point at. A snapshot of what Firebase's own setup gives, overridable because it is Firebase's to choose and not guaranteed to be one address forever; confirm against required_dns_records on the first apply."

    # As given by the custom domain setup on 2026-08-20. There is no IPv6
    # counterpart to put beside it: Firebase serves a custom domain over IPv4
    # only.
    default = ["199.36.158.100"]
}

variable "ipv6_addresses" {
    type = list(string)
    description = "Addresses to publish AAAA records at, or none. Firebase documents no IPv6 support and its own setup asks for AAAA records to be removed; this exists for a caller who has decided to serve over IPv6 anyway, and it is empty unless one has."
    default = []

    # The address that works is 2620:0:890::100, and it is not in Firebase's
    # documentation, not in its setup, and not something Google has undertaken
    # to keep. What that costs if it changes is quiet: dual-stack clients prefer
    # IPv6, so they would fail while every check made over IPv4 goes on passing.
    #
    # It costs something else too, learned the hard way. Hosting resolves the
    # domain when it checks the ACME challenge over HTTP, and it follows AAAA.
    # An AAAA pointing anywhere but Firebase fails that check, and a failed
    # check is a certificate that does not issue -- and later, one that does not
    # renew.
    validation {
        condition     = alltrue([for address in var.ipv6_addresses : strcontains(address, ":")])
        error_message = "ipv6_addresses must be IPv6 addresses. An address without a colon is not one, and an AAAA record holding it resolves nowhere -- which fails the certificate check rather than merely serving nothing."
    }
}

variable "wait_dns_verification" {
    type = bool
    description = "Whether an apply should block until each domain's DNS records verify. Leave false on the apply that creates the domains: the records to publish are an output of those same resources."
    default = false
}
