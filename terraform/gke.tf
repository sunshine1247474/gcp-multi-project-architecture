# ============================================================
# GKE - Google Kubernetes Engine (Project B)
# ============================================================
#
# Private zonal cluster:
#   - Nodes have internal IPs only (no public IPs)
#   - Nodes access internet via Cloud NAT
#   - API server is publicly accessible (for kubectl from Cloud Shell)
#   - Zonal (single zone) = cheaper than regional (3 zones)
#
# The cluster runs:
#   - Nginx Ingress Controller (deployed via kubectl in deploy script)
#   - Flask application (deployed via kubectl in deploy script)
# ============================================================

resource "google_container_cluster" "gke_b" {
  name     = "gke-cluster-b"
  project  = var.project_b
  location = var.zone # Zonal cluster (cheaper, 1 zone instead of 3)

  network    = google_compute_network.vpc_b.name
  subnetwork = google_compute_subnetwork.gke_subnet_b.name

  # We manage the node pool separately (best practice)
  remove_default_node_pool = true
  initial_node_count       = 1

  # VPC-native cluster: pods and services get IPs from secondary ranges
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = true  # Nodes get internal IPs only
    enable_private_endpoint = false # API server is publicly accessible
    master_ipv4_cidr_block  = "172.16.0.0/28" # Control plane IP range
  }

  # Allow kubectl access from anywhere (restrict in production!)
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "All networks"
    }
  }

  # Workload Identity: secure way for pods to authenticate to GCP services
  workload_identity_config {
    workload_pool = "${var.project_b}.svc.id.goog"
  }

  # Allow easy cleanup (disable in production!)
  deletion_protection = false

  # Performance addons
  addons_config {
    dns_cache_config {
      enabled = true
    }
  }

  # Ensure networking and APIs are ready before creating cluster
  depends_on = [
    google_project_service.project_b_container,
    google_compute_router_nat.vpc_b_nat,
  ]
}

# Separately managed node pool (best practice)
resource "google_container_node_pool" "gke_b_nodes" {
  name     = "gke-node-pool-b"
  project  = var.project_b
  location = var.zone
  cluster  = google_container_cluster.gke_b.name

  node_count = var.gke_node_count

  node_config {
    machine_type = var.gke_machine_type
    disk_size_gb = 50          # Minimized to save costs and quota
    disk_type    = "pd-standard" # Standard persistent disk (cheapest)

    # Full cloud-platform scope (IAM controls actual permissions)
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}
