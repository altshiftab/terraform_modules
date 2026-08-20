terraform {
    # A validation that reads another variable -- the service account name check
    # does -- is a 1.9 feature.
    required_version = ">= 1.9.0"

    required_providers {
        google = {
            source = "hashicorp/google"
            version = ">=6.34.0"
        }

        # google_project_service_identity, for the IAP service agent.
        google-beta = {
            source = "hashicorp/google-beta"
            version = ">=6.34.0"
        }
    }
}
