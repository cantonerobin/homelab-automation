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
  default = {
    k3s-nova = "nova"
    k3s-helix = "helix"
    k3s-vega = "vega"
  }
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