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
    # mount = var.features_mount — PVE API only allows root@pam to set non-nesting features.
    # Set via bootstrap: ssh root@<pve-node> "pct set <vmid> -features nesting=1,mount=<type>"
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
