module "netboot_vm" {
  source = "./modules/proxmox_vm"

  name        = "netboot.cantone.net"
  target_node = "vega"
  cores       = 2
  memory      = 2048
  disk_size   = 20

  ip           = var.netboot_network_ip
  gateway      = var.network_vlan_server_gateway
  vlan_tag     = var.network_vlan_server_tag

  template_name  = var.template_name
  nameserver     = var.nameserver
  searchdomain   = var.searchdomain
  ssh_public_key = file("${path.module}/../../ssh/ansible.pub")
}
