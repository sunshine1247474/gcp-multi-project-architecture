# ============================================================
# EXTERNAL LOAD BALANCER + CLOUD ARMOR (Project A)
# ============================================================
#
# This creates the public-facing entry point:
#   Internet -> Static IP -> Forwarding Rule -> HTTP Proxy
#            -> URL Map -> Backend Service (with Cloud Armor)
#            -> [PSC NEG added by deploy script]
#
# The PSC NEG backend is added AFTER Kubernetes creates the
# Internal LB (done by the deploy script, not Terraform).
# ============================================================

# ----------------------------------------------------------
# 1. Static External IP
# ----------------------------------------------------------
# Reserve a static IP so it doesn't change on redeployment
resource "google_compute_global_address" "external_lb_ip" {
  name    = "external-lb-ip"
  project = var.project_a

  depends_on = [google_project_service.project_a_compute]
}

# ----------------------------------------------------------
# 2. Cloud Armor Security Policy (WAF + DDoS Protection)
# ----------------------------------------------------------
# Cloud Armor sits in front of the External LB and can block
# malicious traffic (SQL injection, XSS, geo-blocking, rate limiting)
resource "google_compute_security_policy" "cloud_armor" {
  name    = "cloud-armor-policy"
  project = var.project_a

  # Default rule: allow all traffic
  # In production, add rules to block specific IPs, countries, or attack patterns
  rule {
    action   = "allow"
    priority = "2147483647" # Lowest priority = default/catch-all
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default: allow all traffic"
  }

  depends_on = [google_project_service.project_a_compute]
}

# ----------------------------------------------------------
# 3. Backend Service
# ----------------------------------------------------------
# The backend service defines WHERE traffic goes.
# Initially empty - the PSC NEG is added by the deploy script.
#
# NOTE: No health_checks here! PSC NEG backends use implicit
# health checking based on PSC connection status. GCP does not
# allow explicit health checks on backend services with PSC NEG backends.
resource "google_compute_backend_service" "external_lb" {
  name                  = "external-lb-backend"
  project               = var.project_a
  protocol              = "HTTP"
  timeout_sec           = 30
  load_balancing_scheme = "EXTERNAL_MANAGED"
  security_policy       = google_compute_security_policy.cloud_armor.id

  connection_draining_timeout_sec = 10 # Fast draining for demo

  # The PSC NEG backend is added by the deploy script (not Terraform),
  # so we tell Terraform to ignore backend changes made outside of it.
  lifecycle {
    ignore_changes = [backend]
  }
}

# ----------------------------------------------------------
# 5. URL Map (Routing Rules)
# ----------------------------------------------------------
# Routes incoming requests to the appropriate backend service.
# For this demo, all traffic goes to a single backend.
resource "google_compute_url_map" "external_lb" {
  name            = "external-lb-url-map"
  project         = var.project_a
  default_service = google_compute_backend_service.external_lb.id
}

# ----------------------------------------------------------
# 6. Target HTTP Proxy
# ----------------------------------------------------------
# Terminates HTTP connections and applies the URL map.
# For production, use Target HTTPS Proxy with SSL certificate.
resource "google_compute_target_http_proxy" "external_lb" {
  name    = "external-lb-http-proxy"
  project = var.project_a
  url_map = google_compute_url_map.external_lb.id
}

# ----------------------------------------------------------
# 7. Global Forwarding Rule (Entry Point)
# ----------------------------------------------------------
# This is the actual "listener" - binds the static IP to the proxy.
# External traffic hits this IP on port 80 and enters the LB pipeline.
resource "google_compute_global_forwarding_rule" "external_lb" {
  name                  = "external-lb-forwarding-rule"
  project               = var.project_a
  target                = google_compute_target_http_proxy.external_lb.id
  ip_address            = google_compute_global_address.external_lb_ip.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
