# ============================================================
# NETWORKING - VPCs, Subnets, Firewall Rules, Cloud NAT
# ============================================================
#
# Architecture:
#   Project A (vpc-a) : Edge layer - External LB, PSC consumer
#   Project B (vpc-b) : Backend    - GKE, Internal LB, PSC producer
#
# PSC (Private Service Connect) bridges traffic between projects
# without VPC peering - each project keeps its own network.
# ============================================================

# ----------------------------------------------------------
# 1. Enable Required GCP APIs
# ----------------------------------------------------------
# APIs must be enabled before any resources can be created.

resource "google_project_service" "project_a_compute" {
  project            = var.project_a
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "project_b_compute" {
  project            = var.project_b
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "project_b_container" {
  project            = var.project_b
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

# ----------------------------------------------------------
# 2. VPC Networks (Custom Mode - no auto-created subnets)
# ----------------------------------------------------------

# Project A: VPC for the edge/frontend layer
resource "google_compute_network" "vpc_a" {
  name                    = "vpc-a"
  project                 = var.project_a
  auto_create_subnetworks = false
  description             = "Edge VPC - hosts External LB and PSC consumer endpoint"

  depends_on = [google_project_service.project_a_compute]
}

# Project B: VPC for the backend/application layer
resource "google_compute_network" "vpc_b" {
  name                    = "vpc-b"
  project                 = var.project_b
  auto_create_subnetworks = false
  description             = "Backend VPC - hosts GKE cluster, Internal LB, and PSC producer"

  depends_on = [google_project_service.project_b_compute]
}

# ----------------------------------------------------------
# 3. Subnets
# ----------------------------------------------------------

# Project A: General-purpose subnet
resource "google_compute_subnetwork" "subnet_a" {
  name          = "subnet-a"
  project       = var.project_a
  region        = var.region
  network       = google_compute_network.vpc_a.id
  ip_cidr_range = "10.1.0.0/24"
  description   = "General subnet in VPC A"
}

# Project B: GKE subnet with secondary ranges for Pods and Services
# GKE requires secondary IP ranges for pod and service IPs (VPC-native cluster)
resource "google_compute_subnetwork" "gke_subnet_b" {
  name          = "gke-subnet-b"
  project       = var.project_b
  region        = var.region
  network       = google_compute_network.vpc_b.id
  ip_cidr_range = "10.0.0.0/20" # Node IPs: 10.0.0.0 - 10.0.15.255

  # Secondary ranges are used by GKE for pod and service IPs
  # This is what makes it a "VPC-native" cluster
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.4.0.0/14" # ~260k pod IPs
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.8.0.0/20" # ~4k service IPs
  }

  # Allow GKE nodes to access Google APIs without external IPs
  private_ip_google_access = true
  description              = "GKE node subnet with secondary ranges for pods and services"
}

# Project B: PSC subnet - reserved for Private Service Connect NAT
# PSC uses this subnet to NAT traffic between the consumer and producer
resource "google_compute_subnetwork" "psc_subnet_b" {
  name          = "psc-subnet-b"
  project       = var.project_b
  region        = var.region
  network       = google_compute_network.vpc_b.id
  ip_cidr_range = "10.11.0.0/24"
  purpose       = "PRIVATE_SERVICE_CONNECT"
  description   = "Reserved for PSC Service Attachment NAT"
}

# ----------------------------------------------------------
# 4. Firewall Rules (Project B)
# ----------------------------------------------------------

# Allow GCP health check probes to reach backends
# These IP ranges are Google's health check infrastructure
resource "google_compute_firewall" "allow_health_checks" {
  name    = "vpc-b-allow-health-checks"
  project = var.project_b
  network = google_compute_network.vpc_b.id

  allow {
    protocol = "tcp"
  }

  # Google's health check IP ranges (must be allowed for LB health checks)
  source_ranges = [
    "130.211.0.0/22",
    "35.191.0.0/16",
  ]

  description = "Allow GCP health check probes"
}

# Allow all internal traffic within VPC B
resource "google_compute_firewall" "allow_internal" {
  name    = "vpc-b-allow-internal"
  project = var.project_b
  network = google_compute_network.vpc_b.id

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }

  source_ranges = ["10.0.0.0/8"]
  description   = "Allow all internal traffic within VPC B"
}

# ----------------------------------------------------------
# 5. Cloud NAT (Project B)
# ----------------------------------------------------------
# GKE private nodes have no public IPs, so they need Cloud NAT
# to access the internet (pull container images, etc.)

resource "google_compute_router" "vpc_b_router" {
  name    = "vpc-b-router"
  project = var.project_b
  region  = var.region
  network = google_compute_network.vpc_b.id
}

resource "google_compute_router_nat" "vpc_b_nat" {
  name                               = "vpc-b-nat"
  project                            = var.project_b
  region                             = var.region
  router                             = google_compute_router.vpc_b_router.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
