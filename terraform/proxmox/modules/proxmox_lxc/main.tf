resource "proxmox_lxc" "lxc" {
  hostname    = var.hostname
  target_node = var.target_node
  ostemplate  = var.ostemplate

  cores  = var.cores
  memory = var.memory

  unprivileged = var.unprivileged
  onboot       = true
  start        = true

  ssh_public_keys = var.ssh_public_keys

  nameserver   = var.nameserver
  searchdomain = var.searchdomain

  features {
    nesting = var.features_nesting
  }

  rootfs {
    storage = var.storage
    size    = "${var.disk_size}G"
  }

  network {
    name   = "eth0"
    bridge = var.bridge
    ip     = var.ip
    gw     = var.gateway
  }
}
