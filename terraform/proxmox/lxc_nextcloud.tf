module "nextcloud_lxc" {
  source = "./modules/proxmox_lxc"

  hostname    = "nextcloud"
  target_node = "vega"
  cores       = 4
  memory      = 4096
  disk_size   = 20

  ostemplate      = var.lxc_almalinux9_template
  ssh_public_keys = file("${path.module}/../../ssh/ansible.pub")

  ip           = "${var.nextcloud_lxc_ip}/24"
  gateway      = var.network_vlan_dmz_gateway
  nameserver   = var.nameserver
  searchdomain = var.searchdomain

  bridge           = "DMZ"
  unprivileged     = true
  features_nesting = true   # required for Docker inside LXC
}
