provider "google" {
    project = var.project_id
}
resource "google_compute_network" "apigee_network" {
  name       = "apigee-network"
}
resource "google_compute_global_address" "apigee_range" {
  name          = "apigee-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.apigee_network.id
}
resource "google_service_networking_connection" "apigee_vpc_connection" {
  network                 = google_compute_network.apigee_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.apigee_range.name]
}
locals {
    googleapis = [   "apigee.googleapis.com",
   "cloudkms.googleapis.com",
   "compute.googleapis.com",
   "servicenetworking.googleapis.com"
 ]
 }
resource "google_project_service" "apis" {
     for_each           = toset(local.googleapis)
     project            = var.project_id
     service            = each.key 
     disable_on_destroy = false
     }
resource "google_apigee_organization" "apigeex_org" { 
  analytics_region   = "us-east1"
  project_id         = var.project_id
  authorized_network = google_compute_network.apigee_network.id
  depends_on         = [
    google_service_networking_connection.apigee_vpc_connection,
    //google_project_service.apis.apigee,
  ]
}
resource "google_apigee_environment" "apigee_org_region_env" {
  name         = "apigee-env-dev"
  description  = "apigee-env-dev"
  display_name = "apigee-env-dev"
  org_id       = google_apigee_organization.apigeex_org.id
}
resource "google_apigee_envgroup" "env_grp_dev" {
  name      = "tf-dev-internal"
  hostnames = ["grp.test.com"]
  org_id    = google_apigee_organization.apigeex_org.id
}
resource "google_apigee_instance" "apigee_instance" {
  name     = "apigee-org-instance-us-east1"
  location = "us-east1"
  org_id   = google_apigee_organization.apigeex_org.id
}
resource "google_apigee_instance_attachment" "apigee_instance_attachment" {
  instance_id  = google_apigee_instance.apigee_instance.id
  environment  = google_apigee_environment.apigee_org_region_env.name
}
resource "google_compute_region_backend_service" "producer_service_backend" {
  name          = "producer-service"
  project       = var.project_id
  region        = "us-east1"
  health_checks = [google_compute_health_check.producer_service_health_check.id]
}
resource "google_compute_health_check" "producer_service_health_check" {
  name                = "producer-service-health-check"
  project             = var.project_id
  check_interval_sec  = 1
  timeout_sec         = 1
  tcp_health_check {
    port = "80"
  }
}
data "google_project" "project"{

}

resource "google_compute_forwarding_rule" "apigee_ilb_target_service" {
   name                  = "apigee-forwarding-rule"
   region                = "us-east1"
   project               = var.project_id
   load_balancing_scheme = "INTERNAL"
   backend_service       = google_compute_region_backend_service.producer_service_backend.id
   all_ports             = true
   network               = google_compute_network.apigee_network.id
   //subnetwork            =    "projects/${google_compute_network.apigee_network.id}/regions/us-east1/subnetworks/prv-sn-1"
}