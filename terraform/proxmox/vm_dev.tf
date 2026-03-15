module "dev_vm" {
  source = "./modules/proxmox_vm"

  name        = "dev"
  target_node = "nova"
  cores       = 2
  memory      = 4096
  disk_size   = 20

  ip           = var.dev_vm_ip
  gateway      = var.network_vlan_server_gateway
  template_name  = var.template_name
  nameserver     = var.nameserver
  searchdomain   = var.searchdomain
  ssh_public_key = file("${path.module}/../../ssh/ansible.pub")
}
