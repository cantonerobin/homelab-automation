resource "proxmox_vm_qemu" "vm" {
  name        = var.name
  target_node = var.target_node
  clone       = var.template_name

  hotplug  = "network,disk"
  scsihw   = "virtio-scsi-pci"
  agent    = 1
  memory   = var.memory
  cpu {
    cores = var.cores
    type  = var.cpu_type
    numa  = false
  }

  os_type = "cloud-init"

  ciuser  = "ansible"
  sshkeys = var.ssh_public_key

  bootdisk     = "scsi0"
  ipconfig0    = "ip=${var.ip}/24,gw=${var.gateway}"
  nameserver   = var.nameserver
  searchdomain = var.searchdomain

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  disks {
    ide {
      ide2 {
        cloudinit {
          storage = var.storage
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          storage  = var.storage
          size     = var.disk_size
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
