output "lxc_id" {
  description = "Proxmox LXC container ID"
  value       = proxmox_lxc.lxc.id
}

output "lxc_hostname" {
  description = "LXC container hostname"
  value       = proxmox_lxc.lxc.hostname
}
