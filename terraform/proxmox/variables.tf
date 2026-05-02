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
    node = string
    ip   = string
  }))
  default = {
    k3s-nova  = { node = "nova",  ip = "192.168.10.10" }
    k3s-helix = { node = "helix", ip = "192.168.10.11" }
    k3s-vega  = { node = "vega",  ip = "192.168.10.12" }
  }
}

locals {
  ssh_public_key = file("${path.module}/../../ssh/ansible.pub")
  server_gateway = "192.168.10.1"
  storage        = "local-lvm"
}
