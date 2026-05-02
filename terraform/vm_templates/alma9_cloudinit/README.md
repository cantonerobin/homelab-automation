# AlmaLinux 9 Proxmox Template Builder

Builds reproducible AlmaLinux 9 VM templates on all Proxmox cluster nodes via Ansible.

Two templates are built:

| Template | ID (helix) | ID (nova) | ID (vega) | CIS Hardening |
|----------|-----------|----------|----------|---------------|
| `alma9-template-v1` | 9000 | 9010 | 9020 | Level 1 |
| `alma9-template-dev-v1` | 9001 | 9011 | 9021 | None |

Template IDs are fixed per node (defined in `ansible/inventories/production/host_vars/`).
Terraform clones by name — the provider resolves the correct ID on the target node automatically.

---

## Usage

```bash
# Build both templates on all nodes (parallel)
ansible-playbook ansible/playbooks/proxmox/build_template.yml

# Single node only
ansible-playbook ansible/playbooks/proxmox/build_template.yml -l nova

# Force rebuild (destroys existing templates first)
ansible-playbook ansible/playbooks/proxmox/build_template.yml -e force_rebuild=true
```

## What the Playbook Does

1. Downloads the latest AlmaLinux 9 cloud image (skipped if SHA256 matches upstream)
2. Deploys the cloud-init snippet to `/var/lib/vz/snippets/`
3. Creates a VM, imports the disk, configures hardware
4. Boots the VM — cloud-init runs: packages, Node Exporter, optional CIS Level 1 hardening
5. Waits for shutdown, removes cicustom, converts to template

## Image Updates

When AlmaLinux releases a new image, the upstream CHECKSUM changes.
The next playbook run re-downloads automatically. To rebuild the templates:

```bash
ansible-playbook ansible/playbooks/proxmox/build_template.yml -e force_rebuild=true
```

## Relevant Files

```
ansible/playbooks/proxmox/build_template.yml          # main playbook
ansible/playbooks/proxmox/tasks/build_single_template.yml
ansible/playbooks/proxmox/templates/alma9-cloudinit.yaml.j2
ansible/inventories/production/host_vars/{helix,nova,vega}.yml
```
