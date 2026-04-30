variable "hostname" {
  description = "LXC container hostname"
  type        = string
}

variable "target_node" {
  description = "Proxmox node to place the LXC on"
  type        = string
}

variable "cores" {
  description = "Number of vCPU cores"
  type        = number
}

variable "memory" {
  description = "RAM in MB"
  type        = number
}

variable "disk_size" {
  description = "Root disk size in GB"
  type        = number
  default     = 20
}

variable "storage" {
  description = "Proxmox storage pool for the root disk"
  type        = string
  default     = "local-lvm"
}

variable "ostemplate" {
  description = "CT template (e.g. local:vztmpl/almalinux-9-default_20241120_amd64.tar.xz)"
  type        = string
}

variable "ip" {
  description = "Static IP address with prefix (e.g. 192.168.30.82/24)"
  type        = string
}

variable "gateway" {
  description = "Default gateway"
  type        = string
}

variable "nameserver" {
  description = "DNS server"
  type        = string
}

variable "searchdomain" {
  description = "DNS search domain"
  type        = string
}

variable "ssh_public_keys" {
  description = "SSH public key(s) for the root user"
  type        = string
}

variable "bridge" {
  description = "Network bridge / SDN VNET (e.g. Servers, DMZ)"
  type        = string
  default     = "Servers"
}

variable "unprivileged" {
  description = "Run as unprivileged container"
  type        = bool
  default     = true
}

variable "features_nesting" {
  description = "Enable nesting — required for Docker inside LXC"
  type        = bool
  default     = false
}

variable "features_mount" {
  description = "Allowed mount types (e.g. 'nfs', 'cifs', 'nfs;cifs') — required for NFS/CIFS mounts in unprivileged LXC"
  type        = string
  default     = ""
}
