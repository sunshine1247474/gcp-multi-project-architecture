# ============================================================
# OUTPUTS - Values displayed after terraform apply
# ============================================================
# These are also used by the deploy/destroy scripts via
# "terraform output -raw <name>"
# ============================================================

output "external_lb_ip" {
  description = "External Load Balancer public IP address"
  value       = google_compute_global_address.external_lb_ip.address
}

output "gke_cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.gke_b.name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster API server endpoint"
  value       = google_container_cluster.gke_b.endpoint
  sensitive   = true
}

output "project_a" {
  description = "Project A (Edge/Frontend) ID"
  value       = var.project_a
}

output "project_b" {
  description = "Project B (Backend) ID"
  value       = var.project_b
}

output "region" {
  description = "GCP region"
  value       = var.region
}

output "zone" {
  description = "GCP zone"
  value       = var.zone
}
