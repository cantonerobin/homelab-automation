# AlmaLinux 9 Proxmox Template Builder

This script automatically builds a **reproducible AlmaLinux 9 cloud template** for Proxmox VE.

The template is designed for Infrastructure-as-Code workflows and integrates cleanly with:

* Terraform
* Ansible
* Kubernetes / k3s nodes
* Ceph storage
* Cloud-Init provisioning

The script downloads the latest AlmaLinux cloud image, verifies its checksum, provisions the VM with Cloud-Init, installs updates and required packages, and converts the VM into a reusable Proxmox template.

---

# Features

* Fully automated template creation
* Cloud image checksum verification
* Automatic system updates during template build
* Cloud-Init ready
* Ceph optimized disk configuration
* QEMU Guest Agent enabled
* SSH host key reset
* Machine-ID reset
* Infrastructure-as-Code friendly
* Compatible with Terraform VM cloning

---

# Requirements

This script must be executed on a **Proxmox VE node**.

Required tools:

* `qm`
* `wget`
* `sha256sum`

Required Proxmox configuration:

* storage pool named `ceph_data`
* network bridge `vmbr0`
* snippet storage enabled at

```
/var/lib/vz/snippets
```

The script assumes the following SSH key exists:

```
/root/.ssh/id_rsa.pub
```

---

# What the Script Does

The script performs the following steps:

1. Generate a Cloud-Init configuration
2. Download the latest AlmaLinux 9 cloud image
3. Verify the image checksum
4. Create a new Proxmox VM
5. Import the cloud image disk
6. Attach a Cloud-Init disk
7. Configure VM hardware
8. Boot the VM for provisioning
9. Install updates and required packages
10. Reset machine identity and SSH host keys
11. Shutdown the VM automatically
12. Convert the VM into a reusable template

---

# Template Configuration

The template uses the following Cloud-Init configuration:

* timezone: `Europe/Zurich`
* automatic package updates
* packages installed:

```
qemu-guest-agent
cloud-utils-growpart
git
curl
vim
```

During provisioning the template also:

* enables the QEMU Guest Agent
* resets `/etc/machine-id`
* removes SSH host keys

This ensures every cloned VM receives its own unique identity.

---

# Storage Configuration

The template disk is imported using:

```
virtio-scsi
discard=on
iothread=1
```

These settings improve performance and compatibility when running on **Ceph RBD storage**.

---

# Usage

Make the script executable:

```
chmod +x alma9-template-builder.sh
```

Run the script:

```
./alma9-template-builder.sh
```

If the template already exists, the script will stop.

To force a rebuild of the template use:

```
./alma9-template-builder.sh -f
```

This will:

```
qm destroy 9000 --purge
```

and rebuild the template from scratch.

---

# Result

After successful execution the following template will exist in Proxmox:

```
alma9-template-v1
```

with VM ID:

```
9000
```

This template can be used by Terraform or manually cloned.

---

# Example Terraform Usage

Example Terraform configuration using this template:

```hcl
resource "proxmox_vm_qemu" "k3s_nodes" {

  name        = "k3s-node-1"
  clone       = "alma9-template-v1"
  target_node = "nova"

  cores  = 2
  memory = 4096

  os_type = "cloud-init"

  ciuser  = "ansible"
  sshkeys = file("ssh/ansible.pub")

  ipconfig0 = "ip=dhcp"
}
```

---

# Intended Workflow

This template is designed for the following Infrastructure-as-Code workflow:

```
Template Builder Script
        ↓
Terraform VM creation
        ↓
Cloud-Init initial configuration
        ↓
Ansible provisioning
        ↓
k3s cluster bootstrap
```

---

# Repository Structure (recommended)

```
homelab
│
├─ templates
│   └─ alma9-template-builder.sh
│
├─ terraform
│   └─ proxmox
│
├─ ansible
│   └─ k3s
│
└─ docs
```

---

# Rebuilding the Template

Templates should be rebuilt periodically to ensure updated packages.

Example:

```
./alma9-template-builder.sh -f
```

This will recreate the template with the latest:

* AlmaLinux cloud image
* security updates
* packages

---

# License

This script is provided as-is for homelab and infrastructure automation use.
