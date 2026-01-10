resource "google_project_service" "iap" {
    project = var.project_id
    service = "iap.googleapis.com"
    disable_on_destroy = false
}

resource "google_project_service_identity" "iap" {
    provider = google-beta
    project  = var.project_id
    service  = "iap.googleapis.com"
}

resource "google_cloud_run_service_iam_binding" "binding" {
    project = var.project_id
    service = module.web_service.service.name
    role    = "roles/run.invoker"
    members = [
        google_project_service_identity.iap.member,
    ]
}

resource "google_iap_web_iam_member" "iap_members" {
    for_each = toset(var.members)
    project  = var.project_id
    role     = "roles/iap.httpsResourceAccessor"
    member   = each.key

    depends_on = [google_project_service.iap]
}

resource "google_iap_web_backend_service_iam_binding" "iap_enable" {
    project            = var.project_id
    web_backend_service = module.web_service.backend_service.name
    role               = "roles/iap.httpsResourceAccessor"
    members            = var.members

    depends_on = [google_project_service.iap]
}

module "web_service" {
    source = "../go_web_service"
    project_id = var.project_id
    domain_names = var.domain_names
    image_url = var.image_url
    name = var.name
    region = var.region
    environment_variables = var.environment_variables
    secret_environment_variables = var.secret_environment_variables
    use_http2 = var.use_http2
    execution_environment = var.execution_environment
    enable_iap = true
    existing_service_account_email = var.existing_service_account_email
    vpc_connector = var.vpc_connector
    cloud_sql_connections = var.cloud_sql_connections
}