###############################################################################
# Provider
###############################################################################
terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

###############################################################################
# VPC + subnets
###############################################################################
resource "google_compute_network" "vpc" {
  name                    = "alchemyst-vpc"
  auto_create_subnetworks = false
}

# Public-facing subnet — api-vm only
resource "google_compute_subnetwork" "public" {
  name          = "public-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

# Private subnet — worker VMs live here, no external IPs
resource "google_compute_subnetwork" "private" {
  name                     = "private-subnet"
  ip_cidr_range            = "10.0.1.0/24"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

###############################################################################
# Cloud NAT — lets private VMs reach the internet (apt, pip, npm, model dl)
# without having a public IP themselves.
###############################################################################
resource "google_compute_router" "router" {
  name    = "alchemyst-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "alchemyst-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

###############################################################################
# Firewall rules
###############################################################################

# Allow HTTP (80) and HTTPS (443) from the public internet to api-vm only.
resource "google_compute_firewall" "allow_http_public" {
  name    = "allow-http-public"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["api-vm"]
}

# Allow all internal traffic within the VPC (worker ↔ engine RPC on :49134,
# health-checks, etc.).  Scope is VPC-internal only.
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/16"]
}

# SSH via Identity-Aware Proxy (IAP) — no need to expose port 22 publicly.
resource "google_compute_firewall" "allow_ssh_iap" {
  name    = "allow-ssh-iap"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP's source range — https://cloud.google.com/iap/docs/using-tcp-forwarding
  source_ranges = ["35.235.240.0/20"]
}

###############################################################################
# api-vm  —  public-facing
#   • iii engine (ws :49134, http :3111)
#   • nginx reverse-proxy (:80 → :3111)
###############################################################################
resource "google_compute_instance" "api_vm" {
  name         = "api-vm"
  machine_type = var.api_machine_type
  zone         = var.zone
  tags         = ["api-vm"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = var.disk_size_gb
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.public.id
    # Assigns a public (ephemeral) IP so the world can reach port 80.
    access_config {}
  }

  metadata = {
    ssh-keys       = "${var.ssh_user}:${var.ssh_public_key}"
    startup-script = file("${path.module}/startup-scripts/api-vm.sh")
  }

  # Expose the internal IP to other scripts via metadata so worker VMs
  # can read it and set III_URL at boot time.
  metadata_startup_script = null # overridden above via metadata block

  service_account {
    scopes = ["cloud-platform"]
  }
}

###############################################################################
# caller-vm  —  private, no external IP
#   • caller-worker (TypeScript / Node.js)
###############################################################################
resource "google_compute_instance" "caller_vm" {
  name         = "caller-vm"
  machine_type = var.caller_machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = var.disk_size_gb
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id
    # No access_config → no external IP → not reachable from the public internet
  }

  metadata = {
    ssh-keys       = "${var.ssh_user}:${var.ssh_public_key}"
    # Pass the api-vm's internal IP so the worker knows where to connect.
    api_vm_ip      = google_compute_instance.api_vm.network_interface[0].network_ip
    startup-script = file("${path.module}/startup-scripts/caller-vm.sh")
  }

  service_account {
    scopes = ["cloud-platform"]
  }

  depends_on = [google_compute_instance.api_vm]
}

###############################################################################
# inference-vm  —  private, no external IP
#   • inference-worker (Python + GGUF model)
###############################################################################
resource "google_compute_instance" "inference_vm" {
  name         = "inference-vm"
  machine_type = var.inference_machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 30 # model download needs more headroom
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id
    # No access_config → no external IP
  }

  metadata = {
    ssh-keys       = "${var.ssh_user}:${var.ssh_public_key}"
    api_vm_ip      = google_compute_instance.api_vm.network_interface[0].network_ip
    startup-script = file("${path.module}/startup-scripts/inference-vm.sh")
  }

  service_account {
    scopes = ["cloud-platform"]
  }

  depends_on = [google_compute_instance.api_vm]
}
