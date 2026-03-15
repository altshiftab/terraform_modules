data "google_project" "project" {
  count      = !var.public ? 1 : 0
  project_id = var.project_id
}

resource "google_project_service" "cloud_run" {
  project            = var.project_id
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_service_account" "service_account" {
  count      = var.existing_service_account_email == "" ? 1 : 0
  project    = var.project_id
  account_id = "${var.name}-sa"
}

resource "google_project_iam_member" "cloudsql_client" {
  count   = length(var.cloud_sql_connections) > 0 ? 1 : 0
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${var.existing_service_account_email != "" ? var.existing_service_account_email : google_service_account.service_account[0].email}"
}

resource "google_cloud_run_v2_service" "service" {
  project  = var.project_id
  name     = var.name
  location = var.region
  // Block external requests to the default `.run.app` address.
  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    service_account = var.existing_service_account_email != "" ? var.existing_service_account_email : google_service_account.service_account[0].email
    // The maximum number. Go services should be able to handle a lot of concurrent requests.
    max_instance_request_concurrency = 1000

    execution_environment = var.execution_environment != "" ? var.execution_environment : null

    dynamic "vpc_access" {
      for_each = length(var.network_interfaces) == 0 && var.firewall_config == null ? [] : [1]
      content {
        egress = "ALL_TRAFFIC"

        dynamic "network_interfaces" {
          for_each = var.firewall_config != null ? [{ network = var.firewall_config.network_id, subnetwork = google_compute_subnetwork.egress[0].name }] : var.network_interfaces
          content {
            network    = network_interfaces.value.network
            subnetwork = network_interfaces.value.subnetwork
          }
        }
      }
    }

    containers {
      image = var.image_url
      ports {
        name           = var.use_http2 ? "h2c" : "http1"
        container_port = 8080
      }

      resources {
        startup_cpu_boost = true
      }

      dynamic "volume_mounts" {
        for_each = length(var.cloud_sql_connections) > 0 ? [1] : []
        content {
          name       = "cloudsql"
          mount_path = "/cloudsql"
        }
      }

      dynamic "env" {
        for_each = !var.public ? [1] : []
        content {
          name  = "IAP_JWT_AUDIENCE"
          value = "/projects/${data.google_project.project[0].number}/global/backendServices/${google_compute_backend_service.backend_service.generated_id}"
        }
      }

      dynamic "env" {
        for_each = var.environment_variables
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.secret_environment_variables
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
        }
      }
    }

    dynamic "volumes" {
      for_each = length(var.cloud_sql_connections) > 0 ? [1] : []
      content {
        name = "cloudsql"
        cloud_sql_instance {
          instances = var.cloud_sql_connections
        }
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }
  }

  deletion_protection = false
  depends_on          = [google_project_service.compute, google_project_service.cloud_run]
}

resource "google_compute_region_network_endpoint_group" "network_endpoint_group" {
  project               = var.project_id
  region                = var.region
  name                  = "${var.name}-network-endpoint-group"
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = var.name
  }
}

resource "google_compute_backend_service" "backend_service" {
  project               = var.project_id
  name                  = "${var.name}-backend-service"
  protocol              = var.use_http2 ? "HTTP2" : "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_region_network_endpoint_group.network_endpoint_group.self_link
  }

  iap {
    enabled              = !var.public
    oauth2_client_id     = var.iap_oauth_client_id
    oauth2_client_secret = var.iap_oauth_client_secret
  }
}

# --- Public resources ---

resource "google_cloud_run_service_iam_member" "noauth" {
  count    = var.public ? 1 : 0
  project  = var.project_id
  location = var.region
  service  = google_cloud_run_v2_service.service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# --- Private (IAP) resources ---

resource "google_project_service" "iap" {
  count              = !var.public ? 1 : 0
  project            = var.project_id
  service            = "iap.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service_identity" "iap" {
  count    = !var.public ? 1 : 0
  provider = google-beta
  project  = var.project_id
  service  = "iap.googleapis.com"
}

resource "google_cloud_run_service_iam_binding" "binding" {
  count    = !var.public ? 1 : 0
  project  = var.project_id
  location = var.region
  service  = google_cloud_run_v2_service.service.name
  role     = "roles/run.invoker"
  members = [
    google_project_service_identity.iap[0].member,
  ]
}

resource "google_iap_web_backend_service_iam_binding" "iap_enable" {
  count               = !var.public ? 1 : 0
  project             = var.project_id
  web_backend_service = google_compute_backend_service.backend_service.name
  role                = "roles/iap.httpsResourceAccessor"
  members             = var.members

  depends_on = [google_project_service.iap]
}

resource "google_iap_settings" "iap_settings" {
  count = !var.public ? 1 : 0
  name  = "projects/${data.google_project.project[0].number}/iap_web/compute/services/${google_compute_backend_service.backend_service.name}"

  access_settings {
    cors_settings {
      allow_http_options = true
    }
  }

  depends_on = [google_compute_backend_service.backend_service]
}

# --- Egress firewall ---

locals {
  firewall_name = var.firewall_config != null ? coalesce(var.firewall_config.name, var.name) : null
}

resource "google_compute_subnetwork" "egress" {
  count                    = var.firewall_config != null ? 1 : 0
  project                  = var.firewall_config.project_id
  name                     = "egress-${local.firewall_name}-subnet"
  region                   = var.region
  network                  = var.firewall_config.network_id
  ip_cidr_range            = var.firewall_config.subnetwork_range
  private_ip_google_access = true
}

resource "google_compute_subnetwork_iam_member" "egress_network_user" {
  for_each   = var.firewall_config != null ? toset(var.firewall_config.subnetwork_iam_members) : toset([])
  project    = var.firewall_config.project_id
  region     = var.region
  subnetwork = google_compute_subnetwork.egress[0].name
  role       = "roles/compute.networkUser"
  member     = each.value
}

resource "google_compute_network_firewall_policy_rule" "allow_egress_fqdns" {
  count           = (var.firewall_config != null && length(var.firewall_config.fqdns) > 0) ? 1 : 0
  project         = var.firewall_config.project_id
  firewall_policy = var.firewall_config.firewall_policy
  priority        = var.firewall_config.priority
  direction       = "EGRESS"
  action          = "allow"
  rule_name       = "allow-${local.firewall_name}-egress-fqdns"
  description     = "Allow HTTPS to specific domains."
  enable_logging  = true

  match {
    src_ip_ranges = [var.firewall_config.subnetwork_range]
    dest_fqdns    = var.firewall_config.fqdns

    layer4_configs {
      ip_protocol = "tcp"
      ports       = ["443"]
    }
  }
}