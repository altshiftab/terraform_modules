resource "google_project_service" "compute" {
    project = var.project_id
    service = "compute.googleapis.com"
    disable_on_destroy = false
}

resource "google_project_service" "certificate_manager" {
    project = var.project_id
    service = "certificatemanager.googleapis.com"
    disable_on_destroy = false
}

// URL maps

resource "google_compute_health_check" "dummy_health_check" {
    project = var.project_id
    name = "${var.name}-dummy-health-check"

    http_health_check {
        port_specification = "USE_SERVING_PORT"
    }

    depends_on = [google_project_service.compute]
}

resource "google_compute_backend_service" "dummy_backend_service" {
    project = var.project_id
    name = "${var.name}-dummy-backend-service"
    protocol = "HTTP"
    health_checks = [google_compute_health_check.dummy_health_check.self_link]
    load_balancing_scheme = "EXTERNAL_MANAGED"
}

resource "google_compute_url_map" "url_map_https" {
    project = var.project_id
    name = "${var.name}-url-map-https"

    // Requests with host names other than those specified result in "421 Misdirected Request".
    default_route_action {
        weighted_backend_services {
            backend_service = google_compute_backend_service.dummy_backend_service.self_link
            weight = 100
        }

        fault_injection_policy {
            abort {
                http_status = 421
                percentage = 100
            }
        }
    }

    // Map every set of host names to their corresponding backend service.

    dynamic "host_rule" {
        for_each = var.services

        content {
            hosts = host_rule.value.domain_names
            path_matcher = "${var.name}-url-map-https-path-matcher-${host_rule.key}"
        }
    }

    dynamic "path_matcher" {
        for_each = var.services

        content {
            name = "${var.name}-url-map-https-path-matcher-${path_matcher.key}"
            route_rules {
                priority = 100
                match_rules {
                    prefix_match = "/"
                }

                header_action {
                    request_headers_to_remove  = var.request_headers_to_remove
                    response_headers_to_remove = var.response_headers_to_remove

                    dynamic "request_headers_to_add" {
                        for_each = var.request_headers_to_add

                        content {
                            header_name  = request_headers_to_add.value.header_name
                            header_value = request_headers_to_add.value.header_value
                            replace      = request_headers_to_add.value.replace
                        }
                    }
                }

                route_action {
                    weighted_backend_services {
                        backend_service = path_matcher.value.backend
                        weight          = 100
                    }
                }
            }
            default_service = path_matcher.value.backend
        }
    }
}

// SSL — Certificate Manager

locals {
    all_domains = distinct(flatten([for s in var.services : s.domain_names]))

    services_by_key = { for s in var.services : join(",", sort(s.domain_names)) => s }

    hostname_entries = {
        for pair in flatten([
            for s in var.services : [
                for d in s.domain_names : {
                    domain   = d
                    cert_key = join(",", sort(s.domain_names))
                }
            ]
        ]) : pair.domain => pair
    }
}

resource "google_certificate_manager_dns_authorization" "auth" {
    for_each = toset(local.all_domains)

    project = var.project_id
    name    = "dnsauth-${substr(md5(each.value), 0, 16)}"
    domain  = each.value

    depends_on = [google_project_service.certificate_manager]
}

resource "google_certificate_manager_certificate" "certificates" {
    for_each = local.services_by_key

    project = var.project_id
    name    = "cert-${substr(md5(each.key), 0, 16)}"

    managed {
        domains            = each.value.domain_names
        dns_authorizations = [for d in each.value.domain_names : google_certificate_manager_dns_authorization.auth[d].id]
    }

    lifecycle {
        create_before_destroy = true
    }

    depends_on = [google_project_service.certificate_manager]
}

resource "google_certificate_manager_certificate_map" "map" {
    project = var.project_id
    name    = "${var.name}-cert-map"

    depends_on = [google_project_service.certificate_manager]
}

resource "google_certificate_manager_certificate_map_entry" "entries" {
    for_each = local.hostname_entries

    project      = var.project_id
    name         = "cme-${substr(md5(each.key), 0, 16)}"
    map          = google_certificate_manager_certificate_map.map.name
    hostname     = each.key
    certificates = [google_certificate_manager_certificate.certificates[each.value.cert_key].id]
}

// Proxies

resource "google_compute_ssl_policy" "ssl_policy" {
    project = var.project_id
    name = "${var.name}-ssl-policy"
    min_tls_version = "TLS_1_2"
    profile = "RESTRICTED"

    depends_on = [google_project_service.compute]
}

resource "google_compute_target_https_proxy" "https_proxy" {
    project = var.project_id
    name = "${var.name}-https-proxy-v2"
    url_map = google_compute_url_map.url_map_https.self_link
    certificate_map = "//certificatemanager.googleapis.com/${google_certificate_manager_certificate_map.map.id}"
    ssl_policy = google_compute_ssl_policy.ssl_policy.self_link

    lifecycle {
        create_before_destroy = true
    }
}

// IP addresses

resource "google_compute_global_address" "ipv4_address" {
    project = var.project_id
    name  = "${var.name}-global-address-ipv4"
    ip_version = "IPV4"

    lifecycle {
        prevent_destroy = true
    }

    depends_on = [google_project_service.compute]
}

resource "google_compute_global_address" "ipv6_address" {
    project = var.project_id
    name  = "${var.name}-global-address-ipv6"
    ip_version = "IPV6"

    lifecycle {
        prevent_destroy = true
    }

    depends_on = [google_project_service.compute]
}

// Forwarding rules

resource "google_compute_global_forwarding_rule" "global_forwarding_rule_ipv4_https" {
    project = var.project_id
    name = "${var.name}-forwarding-rule-ipv4"
    target = google_compute_target_https_proxy.https_proxy.self_link
    port_range = "443"
    load_balancing_scheme = "EXTERNAL_MANAGED"
    ip_protocol = "TCP"
    ip_address = google_compute_global_address.ipv4_address.address

    lifecycle {
        create_before_destroy = true
    }
}

resource "google_compute_global_forwarding_rule" "global_forwarding_rule_ipv6_https" {
    project = var.project_id
    name = "${var.name}-forwarding-rule-ipv6"
    target = google_compute_target_https_proxy.https_proxy.self_link
    port_range  = "443"
    load_balancing_scheme = "EXTERNAL_MANAGED"
    ip_protocol = "TCP"
    ip_address  = google_compute_global_address.ipv6_address.address

    lifecycle {
        create_before_destroy = true
    }
}
