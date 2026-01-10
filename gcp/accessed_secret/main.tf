resource "google_project_service" "secret_manager" {
    project = var.project_id
    service = "secretmanager.googleapis.com"
    disable_on_destroy = false
}

resource "google_secret_manager_secret" "accessed_secret" {
    project   = var.project_id
    secret_id = "${var.name_prefix}-secret"
    replication {
        auto {}
    }

    depends_on = [google_project_service.secret_manager]
}

resource "google_secret_manager_secret_version" "accessed_secret" {
    secret = google_secret_manager_secret.accessed_secret.id
    secret_data = var.secret_data
}

resource "google_secret_manager_secret_iam_member" "accessed_secret" {
    for_each = toset(var.accessor_emails)
    project  = var.project_id
    secret_id = google_secret_manager_secret.accessed_secret.id
    role = "roles/secretmanager.secretAccessor"
    member = "serviceAccount:${each.value}"
}
