# Firebase Hosting as an alternative front end to gcp/load_balancer.
#
# The two modules take the same shape on purpose: a name, a project, and a list
# of services each carrying the domain names it answers on. Swapping one for the
# other is a different module block, not a redesign.
#
# The differences cannot be papered over, and are the whole of the decision:
#
#   * Firebase reaches a service over its public run.app URL, so every service
#     fronted this way needs ingress = "INGRESS_TRAFFIC_ALL" and unauthenticated
#     invocation. run.app becomes a second way in that none of this sees, and a
#     service gated by IAP cannot be fronted at all.
#   * Every request cookie except `__session` is stripped, to keep responses
#     cacheable. This is not a detail: the session cookie these services issue
#     is named `session` (the token_cookie_extractor default in utils_go), so
#     switching without renaming it to `__session` -- in the login service that
#     sets it and every service that reads it -- signs everyone out and keeps
#     them out.
#   * Responses are cut off at 60 seconds whatever the service allows.
#   * There is no TLS policy, no Cloud Armor, no header stripping and no 421 for
#     a hostname that was never configured.
#
# Two more to establish before any switch, not verified here: what Host the
# service is handed (Firebase's CDN is a proxy, so host-based routing may need
# X-Forwarded-Host), and which responses the CDN considers cacheable.
#
# What it buys is the forwarding rule bundle: Firebase Hosting has no per-hour
# charge, only storage and transfer.

resource "google_project_service" "firebase" {
    project = var.project_id
    service = "firebase.googleapis.com"
    disable_on_destroy = false
}

resource "google_project_service" "firebase_hosting" {
    project = var.project_id
    service = "firebasehosting.googleapis.com"
    disable_on_destroy = false
}

# Adding Firebase to a project is a once-ever operation: the call behind this
# returns 409 if the project already has it, and the resource then has to be
# imported rather than created. Set create_firebase_project = false in a project
# that has already been through it, or when a second instance of this module
# shares the project.
resource "google_firebase_project" "project" {
    count = var.create_firebase_project ? 1 : 0

    provider = google-beta
    project = var.project_id

    depends_on = [google_project_service.firebase]
}

locals {
    # Keyed by service rather than by the set of domains it answers on. The
    # domain set is what gcp/load_balancer keys its certificates by, and copying
    # that here would be a trap: a site id is ForceNew on every resource below
    # it, so adding one domain to a service would destroy and recreate the site,
    # its version, its release and the custom domain of every *unchanged* domain
    # on that service -- a new ownership TXT record and a reissued certificate,
    # with the service dark until DNS is republished and verified. Certificates
    # tolerate that because they are replaced create-before-destroy; a domain
    # cannot be, since it may only be attached to one site at a time.
    services_by_key = { for s in var.services : s.service_name => s }

    # Derived here rather than read back off the resource so that everything
    # built from a site id -- the ownership record below, above all -- is known
    # while planning, and can be managed with for_each rather than published by
    # hand after an apply.
    site_ids = {
        for key in keys(local.services_by_key) :
        key => "${var.name}-${substr(md5("${var.project_id}/${key}"), 0, 16)}"
    }

    hostname_entries = {
        for pair in flatten([
            for s in var.services : [
                for d in s.domain_names : {
                    domain   = d
                    site_key = s.service_name
                }
            ]
        ]) : pair.domain => pair
    }
}

// Sites

# The identifier is a digest rather than the service's own name because a site
# id is claimed from a namespace shared with every other Firebase project, and
# "altshift-www" is exactly the kind of name that is already taken. The project
# id goes into the digest so two projects fronting the same services do not
# collide either.
resource "google_firebase_hosting_site" "sites" {
    for_each = local.services_by_key

    provider = google-beta
    project = var.project_id
    site_id = local.site_ids[each.key]

    depends_on = [google_firebase_project.project, google_project_service.firebase_hosting]
}

// Routing

# Every request is handed straight to the service; nothing is served from
# Hosting itself. That is what keeps the whole configuration expressible here --
# a site with no files to upload needs no firebase.json and no Firebase CLI, so
# none of this has to leave Terraform.
#
# Each service states its region and the module writes it out; there is no
# default here on purpose. Omitting the field does not mean "wherever the
# service is", it means us-central1, which would route every request across an
# ocean and still appear to work, so the one thing this must never do is leave
# it to be inferred.
resource "google_firebase_hosting_version" "versions" {
    for_each = local.services_by_key

    provider = google-beta
    site_id = google_firebase_hosting_site.sites[each.key].site_id

    config {
        rewrites {
            glob = "**"

            run {
                service_id = each.value.service_name
                region = each.value.region
            }
        }
    }
}

resource "google_firebase_hosting_release" "releases" {
    for_each = local.services_by_key

    provider = google-beta
    site_id = google_firebase_hosting_site.sites[each.key].site_id
    version_name = google_firebase_hosting_version.versions[each.key].name
    message = "Released by Terraform."
}

// Domains

# The records a domain needs are in the dns_records output, derived rather than
# read back, so the caller can publish them in the same apply that creates this.
# wait_dns_verification is still off by default: DNS the apply just wrote has to
# propagate before Firebase can see it, and an apply is a poor place to wait out
# a TTL. Turn it on once the records are live, or leave it off and let the next
# plan report the domain as verified.
#
# required_dns_records is the other side of it -- what Firebase says is still
# missing, which is what to read when a domain does not verify and the derived
# records are suspected of being wrong.
resource "google_firebase_hosting_custom_domain" "domains" {
    for_each = local.hostname_entries

    provider = google-beta
    project = var.project_id
    site_id = google_firebase_hosting_site.sites[each.value.site_key].site_id
    custom_domain = each.value.domain

    wait_dns_verification = var.wait_dns_verification

    depends_on = [google_firebase_hosting_release.releases]
}
