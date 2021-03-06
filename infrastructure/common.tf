# Configure the Google Cloud provider
provider "google" {
  credentials = "${file("gcloud.json")}"
  project     = "saltstack-handson"
  region      = "europe-west1"
}

# Create a network for handson
resource "google_compute_network" "default" {
    name = "salt"
    ipv4_range = "10.0.0.0/8"
}

# Create Firewall specific for Salt Handson
resource "google_compute_firewall" "external" {
    name = "external"
    network = "${google_compute_network.default.name}"

    description = "Firewall rules to allow ssh and web from anywhere"

    allow {
        protocol = "icmp"
    }

    allow {
        protocol = "tcp"
        ports = ["22", "80", "8080"]
    }

    source_ranges = ["0.0.0.0/0"]
    depends_on = ["google_compute_network.default"]
}

resource "google_compute_firewall" "internal" {
    name = "internal"
    network = "${google_compute_network.default.name}"
    description = "Firewall rules to allow all traffic inside the project network"

    allow {
        protocol = "icmp"
    }

    allow {
        protocol = "tcp"
        ports = ["0-65535"]
    }

    source_ranges = ["10.0.0.0/8"]
    depends_on = ["google_compute_network.default"]
}

# Master of Master for all infrastructure
resource "google_compute_instance" "root" {
    name = "central-master"
    machine_type = "g1-small"
    zone = "europe-west1-b"
    tags = ["master", "salt"]
    can_ip_forward = true

    // Local SSD disk
    disk {
        image = "${var.image}"
    }

    network_interface {
        network = "salt"
        access_config {
            // Ephemeral IP
        }
    }

    metadata {
        grains = <<EOG
roles:
  - master
EOG
        master = "localhost"
    }

    metadata_startup_script = "${file("master-bootstrap.sh")}"

    service_account {
        scopes = ["compute-ro", "storage-ro"]
    }

    depends_on = ["google_compute_network.default"]
}


resource "google_dns_record_set" "central-master" {
    managed_zone = "${var.zone}"
    name = "central-master.${var.domain}"
    type = "A"
    ttl = 300
    rrdatas = ["${google_compute_instance.root.network_interface.0.access_config.0.nat_ip}"]
    depends_on = ["google_compute_instance.root"]
}


resource "google_compute_route" "nat" {
    name = "nat-gateway"
    dest_range = "0.0.0.0/0"
    network = "salt"
    next_hop_instance = "central-master"
    next_hop_instance_zone = "europe-west1-b"
    priority = 800
    tags = ["nat"]
    depends_on = ["google_compute_instance.root"]
}


