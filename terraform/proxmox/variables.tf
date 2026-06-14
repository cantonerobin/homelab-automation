variable "pm_api_url" {
  description = "Proxmox API endpoint"
  type        = string
}

variable "pm_api_token_id" {
  description = "Proxmox API token (e.g. root@pam!terraform)"
  type        = string
  sensitive   = true
}

variable "pm_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "template_name" {
  type    = string
  default = "alma9-template-v1"
}

variable "nameserver" {
  type    = string
  default = "192.168.1.2"
}

variable "searchdomain" {
  type    = string
  default = "cantone.net"
}

variable "k3s_nodes" {
  type = map(object({
    node       = string
    ip         = string # VLAN 10 — Server (Ansible, internal services)
    cluster_ip = string # VLAN 5  — k3s Cluster (etcd, Flannel overlay)
    dmz_ip     = string # VLAN 30 — DMZ (Traefik external entrypoint)
  }))
  default = {
    k3s-nova  = { node = "nova",  ip = "192.168.10.31", cluster_ip = "192.168.5.31", dmz_ip = "192.168.30.31" }
    k3s-helix = { node = "helix", ip = "192.168.10.32", cluster_ip = "192.168.5.32", dmz_ip = "192.168.30.32" }
    k3s-vega  = { node = "vega",  ip = "192.168.10.33", cluster_ip = "192.168.5.33", dmz_ip = "192.168.30.33" }
  }
}

locals {
  ssh_public_key = file("${path.module}/../../ssh/ansible.pub")
  server_gateway = "192.168.10.1"
  storage        = "local-lvm"
}
