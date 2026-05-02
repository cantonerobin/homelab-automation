resource "proxmox_vm_qemu" "netboot" {
  name        = "netboot"
  target_node = "vega"
  clone       = var.template_name

  hotplug  = "network,disk"
  scsihw   = "virtio-scsi-pci"
  agent    = 1
  memory   = 2048
  cpu {
    cores = 2
    type  = "host"
    numa  = false
  }

  os_type      = "cloud-init"
  ciuser       = "ansible"
  sshkeys      = local.ssh_public_key
  bootdisk     = "scsi0"
  ipconfig0    = "ip=192.168.10.156/24,gw=${local.server_gateway}"
  nameserver   = var.nameserver
  searchdomain = var.searchdomain

  network {
    id     = 0
    model  = "virtio"
    bridge = "Servers"
  }

  disks {
    ide {
      ide2 {
        cloudinit {
          storage = local.storage
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          storage  = local.storage
          size     = 20
          iothread = true
          discard  = true
        }
      }
    }
  }

  vga {
    type = "std"
  }
}
