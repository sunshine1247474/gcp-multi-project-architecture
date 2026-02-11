# ============================================================
# VARIABLES - Input parameters for the deployment
# ============================================================
# Set these in terraform.tfvars (copy from terraform.tfvars.example)
# ============================================================

variable "project_a" {
  description = "GCP Project ID for Project A (Edge/Frontend - hosts External LB, Cloud Armor, PSC consumer)"
  type        = string
}

variable "project_b" {
  description = "GCP Project ID for Project B (Backend - hosts GKE, Internal LB, Nginx Ingress, Flask app, PSC producer)"
  type        = string
}

variable "region" {
  description = "GCP region for all regional resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for GKE cluster (zonal = cheaper than regional)"
  type        = string
  default     = "us-central1-a"
}

variable "gke_node_count" {
  description = "Number of nodes in the GKE node pool"
  type        = number
  default     = 2
}

variable "gke_machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-medium"
}
