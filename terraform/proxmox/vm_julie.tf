resource "proxmox_vm_qemu" "julie" {
  name        = "habit-tracker"
  target_node = "vega"
  clone       = "alma9-template-dev-v1"

  hotplug  = "network,disk"
  scsihw   = "virtio-scsi-pci"
  agent    = 1
  memory   = 4096
  cpu {
    cores = 2
    type  = "host"
    numa  = false
  }

  os_type      = "cloud-init"
  ciuser       = "ansible"
  sshkeys      = local.ssh_public_key
  bootdisk     = "scsi0"
  ipconfig0    = "ip=192.168.30.69/24,gw=192.168.30.1"
  nameserver   = var.nameserver
  searchdomain = var.searchdomain

  network {
    id     = 0
    model  = "virtio"
    bridge = "DMZ"
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
          size     = 50
          iothread = true
          discard  = true
        }
      }
    }
  }

  vga {
    type = "std"
  }

  lifecycle {
    ignore_changes = [target_node]
  }
}
