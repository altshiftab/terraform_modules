resource "google_cloud_run_service_iam_member" "noauth" {
    project = var.project_id
    service = module.web_service.service.name
    role    = "roles/run.invoker"
    member  = "allUsers"
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
    existing_service_account_email = var.existing_service_account_email
    vpc_connector = var.vpc_connector
    cloud_sql_connections = var.cloud_sql_connections
}