output "sites" {
    description = "The site serving each domain name."
    value = {
        for domain, entry in local.hostname_entries :
        domain => {
            site_id     = google_firebase_hosting_site.sites[entry.site_key].site_id
            default_url = google_firebase_hosting_site.sites[entry.site_key].default_url
        }
    }
}

# NOT the counterpart of gcp/load_balancer's dns_authorizations, however much it
# looks like one. That output is a declaration: a fixed record per domain, safe
# to drive `for_each` over and manage as Cloud DNS resources.
#
# This is a reconciliation report -- Firebase's answer, as of `check_time`, to
# "what is still missing". It empties once the records are in place and
# verified, and its contents shift as checks re-run. Driving managed records
# from it would delete them on the apply after the one that satisfied it, and
# then flap: apply, publish, verify, next apply takes the site down.
#
# Read it, publish what it names by hand or into a static configuration, and do
# not wire it into `for_each`.
output "required_dns_records" {
    description = "What Firebase reports is still missing from DNS for each domain, at the time of the last check. Point-in-time and empties once satisfied -- read it, do not drive managed records from it."
    value = {
        for domain, resource in google_firebase_hosting_custom_domain.domains :
        domain => flatten([
            for update in resource.required_dns_updates : [
                for desired in update.desired : [
                    for record in desired.records : {
                        name = record.domain_name
                        type = record.type
                        data = record.rdata
                    }
                ]
            ]
        ])
    }
}

# The records the caller publishes, derived rather than read back, so they can
# be managed the way gcp/load_balancer's dns_authorizations are: known while
# planning, stable across applies, safe to drive for_each over.
#
# The TXT is what proves ownership, and Firebase reads it again at every
# renewal rather than only at setup -- taking it out later stops certificates
# being reissued. Its value is `hosting-site=<site id>`, which this module
# already knows.
#
# `data` is unquoted. Cloud DNS wants a TXT value quoted in its rrdatas, the way
# the caller already quotes its SPF and DMARC records.
#
# AAAA records are emitted only for a caller that set ipv6_addresses. Firebase
# documents no IPv6 support and asks for AAAA records to be removed, so a name
# left to the default loses IPv6 in the move; see that variable for what opting
# back in rests on.
output "dns_records" {
    description = "The DNS records each domain needs, derived from configuration and known at plan time. TXT values are unquoted."
    value = {
        for domain, entry in local.hostname_entries :
        domain => concat(
            [for address in var.ip_addresses : { type = "A", data = address }],
            [for address in var.ipv6_addresses : { type = "AAAA", data = address }],
            [{ type = "TXT", data = "hosting-site=${local.site_ids[entry.site_key]}" }],
        )
    }
}
