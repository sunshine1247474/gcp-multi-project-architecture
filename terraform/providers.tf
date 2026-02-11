# ============================================================
# PROVIDERS - Terraform & Google Cloud configuration
# ============================================================
# We use the Google provider to manage GCP resources.
# No default project is set because resources span TWO projects.
# Each resource explicitly specifies its project.
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

provider "google" {
  # No default project - each resource specifies its own project
  # Authentication: uses Application Default Credentials (ADC)
  #   gcloud auth application-default login
  region = var.region
}
