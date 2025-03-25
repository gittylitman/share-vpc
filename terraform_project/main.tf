terraform {
  backend "gcs" {
    bucket  = "vpc-kpmg"
    prefix  = "state"
  }
}

provider "google" {
  project = "host-454313"
}

data "google_secret_manager_regional_secret_version" "cert" {
  secret   = "certificate"
  location = "me-west1"
}

data "google_secret_manager_regional_secret_version" "pk" {
  secret   = "priavte-key"
  location = "me-west1"
}

resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "time_sleep" "wait_60_seconds" {
  create_duration = "60s"
  depends_on = [ google_project_service.compute ]
}

resource "google_compute_region_network_endpoint_group" "serverless_neg" {
  name                  = "neg"
  region                = "me-west1"
  network_endpoint_type = "SERVERLESS"
  cloud_run {
    service = "hello-shared"
  }
  depends_on = [ time_sleep.wait_60_seconds ]
}

resource "google_compute_region_backend_service" "backend_service" {
  name                  = "bsrv"
  region                = "me-west1"
  load_balancing_scheme = "INTERNAL_MANAGED"
  protocol              = "HTTPS"
  backend {
    group = google_compute_region_network_endpoint_group.serverless_neg.id
  }
}

resource "google_compute_region_url_map" "url_map" {
  name   = "lb"
  region = "me-west1"

  default_service = google_compute_region_backend_service.backend_service.id

  host_rule {
    hosts        = ["*"]
    path_matcher = "path-matcher"
  }

  path_matcher {
    name = "path-matcher"

    default_service = google_compute_region_backend_service.backend_service.id

    path_rule {
      paths   = ["/GetResult"]
      service = google_compute_region_backend_service.backend_service.id
    }

    path_rule {
      paths   = ["/GetSummary"]
      service = google_compute_region_backend_service.backend_service.id
    }
  }
}

resource "google_compute_region_ssl_certificate" "certi" {
  region   = "me-west1"
  name        = "ceeer"
  private_key = data.google_secret_manager_regional_secret_version.pk.secret_data
  certificate = data.google_secret_manager_regional_secret_version.cert.secret_data

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [ data.google_secret_manager_regional_secret_version.pk, data.google_secret_manager_regional_secret_version.cert ]
}

data "google_compute_subnetwork" "proxy_subnet" {
  name          = "snet-test-proxy-only-binom"
  region        = "me-west1"
  project = "gantt-host-project"
}

resource "google_compute_region_target_https_proxy" "https_proxy" {
  name            = "https-proxy"
  region          = "me-west1"
  url_map         = google_compute_region_url_map.url_map.id
  ssl_certificates = [google_compute_region_ssl_certificate.certi.id]
  depends_on = [google_compute_region_ssl_certificate.certi]
}

resource "google_compute_forwarding_rule" "https_forwarding_rule" {
  name                  = "https_forwarding_rule"
  region                = "me-west1"
  load_balancing_scheme = "INTERNAL_MANAGED"
  target                = google_compute_region_target_https_proxy.https_proxy.self_link
  port_range            = "443"
  network               = "projects/gantt-host-project/global/networks/binom-dev"
  subnetwork            = "projects/gantt-host-project/regions/me-west1/subnetworks/snet-test-binom"
  depends_on = [ data.google_compute_subnetwork.proxy_subnet ]
}
