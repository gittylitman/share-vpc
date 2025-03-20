terraform {
  backend "gcs" {
    bucket  = "vpc-kpmg"
    prefix  = "state"
  }
}

provider "google" {
  project = "host-454313"
}

resource "google_compute_shared_vpc_host_project" "host" {
  project = "host-454313"
}

resource "google_compute_shared_vpc_service_project" "service1" {
  host_project    = google_compute_shared_vpc_host_project.host.project
  service_project = "try-vpm"
}
