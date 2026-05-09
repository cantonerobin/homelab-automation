# Subnet groups — used in firewall_rules.tf as src/dst.
# These replace the broken built-in network aliases in Traffic Rules.

resource "unifi_firewall_group" "network_mgmt" {
  name    = "MGMT-subnet"
  type    = "address-group"
  members = ["192.168.1.0/24"]
}

resource "unifi_firewall_group" "network_k3s" {
  name    = "k3s-cluster-subnet"
  type    = "address-group"
  members = ["192.168.5.0/24"]
}

resource "unifi_firewall_group" "network_server" {
  name    = "Server-subnet"
  type    = "address-group"
  members = ["192.168.10.0/24"]
}


resource "unifi_firewall_group" "network_client" {
  name    = "Client-subnet"
  type    = "address-group"
  members = ["192.168.20.0/24"]
}

resource "unifi_firewall_group" "network_dmz" {
  name    = "DMZ-subnet"
  type    = "address-group"
  members = ["192.168.30.0/24"]
}



resource "unifi_firewall_group" "network_iot" {
  name    = "IoT-subnet"
  type    = "address-group"
  members = ["192.168.40.0/24"]
}



resource "unifi_firewall_group" "network_all" {
  name    = "Private-all"
  type    = "address-group"
  members = [
    "192.168.0.0/16"
  ]
}

resource "unifi_firewall_group" "hosts_dns-server" {
  name    = "DNS-servers"
  type    = "address-group"
  members = [
    "192.168.1.2",   # pi01 AdGuard primary
    "192.168.1.3",   # pi02 AdGuard secondary
  ]
}