terraform {
    # Cross-variable references in a validation block, which supported_regions
    # relies on, are a 1.9 feature.
    required_version = ">= 1.9.0"

    required_providers {
        google = {
            source = "hashicorp/google"
            version = ">=6.34.0"
        }

        # Every Firebase resource here is beta-only.
        google-beta = {
            source = "hashicorp/google-beta"
            version = ">=6.34.0"
        }
    }
}
