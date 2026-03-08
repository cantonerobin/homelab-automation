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

variable "template_id" {
  default = 9000
}

variable "k3s_nodes" {
  default = {
    k3s-nova = "nova"
    k3s-helix = "helix"
    k3s-vega = "vega"
  }
}