variable "unifi_username" {
  description = "Local Unifi admin username"
  type        = string
}

variable "unifi_password" {
  description = "Local Unifi admin password"
  type        = string
  sensitive   = true
}

variable "unifi_api_url" {
  description = "Unifi controller URL (e.g. https://192.168.1.1)"
  type        = string
  default     = "https://192.168.1.1"
}
