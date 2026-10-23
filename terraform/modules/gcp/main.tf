variable "name" { type = string }
variable "admin_cidr" { type = string }
variable "ssh_key" { type = string }
variable "startup" { type = string }

terraform {
  required_providers {
    google = { source = "hashicorp/google" }
  }
}
resource "google_compute_network" "lab" {
  name                    = var.name
  auto_create_subnetworks = false
}
resource "google_compute_subnetwork" "lab" {
  name          = var.name
  ip_cidr_range = "10.30.1.0/24"
  region        = "us-central1"
  network       = google_compute_network.lab.id
}
resource "google_compute_firewall" "http" {
  name          = "${var.name}-http"
  network       = google_compute_network.lab.name
  source_ranges = ["0.0.0.0/0"]
  target_tags   = [var.name]
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}
resource "google_compute_firewall" "ssh" {
  name          = "${var.name}-ssh"
  network       = google_compute_network.lab.name
  source_ranges = [var.admin_cidr]
  target_tags   = [var.name]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
resource "google_compute_instance" "lab" {
  name         = var.name
  machine_type = "e2-micro"
  zone         = "us-central1-a"
  tags         = [var.name]
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = 30
      type  = "pd-standard"
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.lab.id
    access_config {}
  }
  metadata                = { ssh-keys = "labadmin:${var.ssh_key}", enable-oslogin = "FALSE" }
  metadata_startup_script = var.startup
  shielded_instance_config { enable_vtpm = true }
}
resource "google_storage_bucket" "lab" {
  name                        = "${var.name}-gcp"
  location                    = "US-CENTRAL1"
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  soft_delete_policy { retention_duration_seconds = 0 }
}
output "ip" { value = google_compute_instance.lab.network_interface[0].access_config[0].nat_ip }
output "bucket" { value = google_storage_bucket.lab.name }
