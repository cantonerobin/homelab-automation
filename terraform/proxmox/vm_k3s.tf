resource "proxmox_vm_qemu" "k3s_nodes" {

  for_each = var.k3s_nodes

    name        = each.key
    target_node = each.value
    clone       = "alma9-template-v1"
    
    numa = true
    hotplug  = "network,disk,cpu,memory"
    cores  = 2
    memory = 4096

    os_type = "cloud-init"

    ciuser  = "ansible"
    cipassword = "test123"
    sshkeys = file("${path.module}/ssh/ansible.pub")

    bootdisk = "scsi0"

    ipconfig0 = "ip=dhcp"
    nameserver = "192.168.10.1"
    searchdomain = "cantone.net"

    network {
      model  = "virtio"
      bridge = "vmbr0"
    }

  disks {
    scsi {
      scsi0 {
        disk {
          storage = "ceph_data"
          size    = 40
        }
      }
    }
  }
  vga {
    type = "std"
  }
}