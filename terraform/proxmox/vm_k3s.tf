resource "proxmox_vm_qemu" "k3s" {
  for_each = var.k3s_nodes

  name        = each.key
  target_node = each.value.node
  clone       = var.template_name

  start_at_node_boot   = true
  hotplug  = "network,disk"
  scsihw   = "virtio-scsi-pci"
  agent    = 1
  memory   = 12288
  balloon  = 0
  cpu {
    cores = 4
    type  = "host"
    numa  = false
  }

  os_type      = "cloud-init"
  ciuser       = "ansible"
  sshkeys      = local.ssh_public_key
  bootdisk     = "scsi0"
  ipconfig0    = "ip=${each.value.cluster_ip}/24"
  ipconfig1    = "ip=${each.value.ip}/24,gw=${local.server_gateway}"
  ipconfig2    = "ip=${each.value.dmz_ip}/24"
  nameserver   = var.nameserver
  searchdomain = var.searchdomain

  # eth0 — VLAN 5 k3s Cluster (etcd, Flannel overlay, --flannel-iface eth0)
  network {
    id     = 0
    model  = "virtio"
    bridge = "k3s"
  }

  # eth1 — VLAN 10 Server (default gateway, Ansible, internal services)
  network {
    id     = 1
    model  = "virtio"
    bridge = "Servers"
  }

  # eth2 — VLAN 30 DMZ (Traefik external entrypoint)
  network {
    id     = 2
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
          size     = 40
          iothread = true
          discard  = true
        }
      }
    }
    virtio {
      virtio0 {
        disk {
          storage  = local.storage
          size     = 100
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
