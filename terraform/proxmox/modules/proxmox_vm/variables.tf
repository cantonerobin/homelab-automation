variable "name" {
  description = "VM name"
  type        = string
}

variable "target_node" {
  description = "Proxmox node to place the VM on"
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
  description = "OS disk size in GB"
  type        = number
  default     = 20
}

variable "storage" {
  description = "Proxmox storage pool for VM disks"
  type        = string
  default     = "ceph_data"
}

variable "template_name" {
  description = "Name of the Proxmox template to clone"
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

variable "ssh_public_key" {
  description = "SSH public key content for the ansible user"
  type        = string
}

variable "ip" {
  description = "Static IP address for the VM (without prefix, e.g. 192.168.10.10)"
  type        = string
}

variable "gateway" {
  description = "Default gateway for the VM"
  type        = string
}

variable "cpu_type" {
  description = "CPU type. host = max performance + nested virt. Only use kvm64 for cross-generation live migration."
  type        = string
  default     = "host"
}
