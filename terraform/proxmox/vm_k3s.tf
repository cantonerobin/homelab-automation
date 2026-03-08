resource "proxmox_vm_qemu" "k3s_nodes" {

  for_each = var.k3s_nodes

    name        = each.key
    target_node = each.value
    clone       = var.template_name
    
    numa = true
    hotplug  = "network,disk,cpu,memory"
    scsihw   = "virtio-scsi-pci"
    agent    = 1
    cores    = 2
    memory   = 4096

    os_type = "cloud-init"

    ciuser  = "ansible"
    cipassword = "test123"
    sshkeys = file("${path.module}/ssh/ansible.pub")

    bootdisk = "scsi0"

    ipconfig0 = "ip=dhcp"
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
          storage = "ceph_data"
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          storage  = "ceph_data"
          size     = 40
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