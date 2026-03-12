variable "pm_api_url" {
  description = "Proxmox API endpoint"
  type        = string
}

variable "pm_api_token_id" {
  description = "Proxmox API token ID"
  type        = string
  sensitive   = true
}

variable "pm_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "template_name" {
  description = "Name of the Proxmox template to clone"
  type        = string
  default     = "alma9-template-v1"
}

variable "k3s_nodes" {
  type = map(object({
    node = string
    ip   = string
  }))
  default = {
    k3s-nova = { node = "nova",  ip = "192.168.10.10" }
    k3s-helix = { node = "helix", ip = "192.168.10.11" }
    k3s-vega = { node = "vega",  ip = "192.168.10.12" }
  }
}

variable "network_vlan_server_gateway" {
  description = "Gateway for Hosts in the Server Vlan"
  type        = string
  default     = "192.168.10.1"
}

variable "network_vlan_server_tag" {
  description = "VLAN tag for Servers"
  type        = number
  default     = 10
}

variable "netboot_network_ip" {
  description = "IP for the netboot Host"
  type        = string
  default     = "192.168.10.156"
}


variable "nameserver" {
  description = "DNS server for VMs"
  type        = string
  default     = "192.168.10.1"
}

variable "searchdomain" {
  description = "DNS search domain for VMs"
  type        = string
  default     = "cantone.net"
}