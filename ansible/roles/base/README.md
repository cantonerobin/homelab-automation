# vm_base

Base configuration for all AlmaLinux 9 VMs after OS installation.

## Usage

```bash
# All VMs in a group
ansible-playbook ansible/vm_base.yml -e target=mediastack

# Single host
ansible-playbook ansible/vm_base.yml -e target=mediastack
```

## What this role does

1. Set hostname
2. Install base packages: `qemu-guest-agent`, `git`, `curl`, `vim`
3. Start + enable `qemu-guest-agent`
4. Create `ansible` user + group, deploy SSH key, passwordless sudo
5. Harden SSH: disable password auth, disable root login

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ansible_ssh_public_key` | (in defaults) | SSH public key for the ansible user |

## Prerequisites

- AlmaLinux 9 freshly installed
- SSH access as root (for bootstrap) or as ansible user (for re-runs)
- `sshpass` on the control node (for initial password auth bootstrap)
