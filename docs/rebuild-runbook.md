# Homelab — Rebuild Runbook

> Step-by-step guide to build the entire infrastructure from scratch.
> Order is mandatory — later steps have dependencies on earlier ones.
> Last updated: 2026-03-28

---

## Prerequisites (once, locally)

```bash
# SSH keypair is in ssh/ansible (gitignored) + ssh/ansible.pub (committed)
# If regenerating:
ssh-keygen -t ed25519 -C "ansible@homelab" -f ssh/ansible

# Terraform
terraform -version  # >= 1.0

# Ansible
ansible --version   # >= 2.14
ansible-galaxy collection install -r ansible/requirements.yml

# Create terraform.tfvars (gitignored)
cp terraform/proxmox/terraform.tfvars.example terraform/proxmox/terraform.tfvars
# → fill in pm_api_url, pm_api_token_id, pm_api_token_secret
```

---

## Step 1 — Network (Unifi)

> Configured once, should persist. Only relevant during a complete Unifi reset.

- Create VLANs: 2 (Mgmt), 10 (Server), 20 (Client), 30 (DMZ), 40 (Untrust)
- Configure trunk ports on switch ports of PVE nodes (all VLANs tagged)
- DHCP Option 66/67 on VLAN 10 → `192.168.10.156` (netboot.xyz, for PXE boot)
- Static IPs / DHCP reservations:

| Host | IP |
|------|----|
| helix | 192.168.10.20 |
| vega | 192.168.10.21 |
| nova | 192.168.10.22 |
| truenas | 192.168.10.25 |

---

## Step 2 — Install TrueNAS Scale (truenas)

1. Boot TrueNAS Scale ISO (USB or netboot.xyz)
2. Install on **2x 250GB SATA SSD** (mirror)
3. **Enable SSH:** System → Services → SSH → Start + Enable
4. **Add Ansible SSH key:**
   - System → Shell or directly via WebUI terminal:
   ```bash
   mkdir -p /root/.ssh
   echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK/8o2JjMARfA9ZTghcgksuK4tNU2POnQr0Tz5tMyqfS ansible@homelab" >> /root/.ssh/authorized_keys
   chmod 600 /root/.ssh/authorized_keys
   ```
5. Test connection:
   ```bash
   ssh -i ssh/ansible root@<ip>
   ```

---

## Step 3 — Configure TrueNAS via Ansible

> Configures: ZFS pools, datasets, zvols, NFS, snapshots, scrubs, VMs, network.
> Prerequisite: Step 2 complete, disks physically installed (4x 3TB + 1x 6TB).

```bash
# Temporarily adjust IP in vars/config.yml to current DHCP IP if needed
# ansible/truenas/vars/config.yml → truenas_ip

cd ansible
ansible-playbook truenas/configure.yml
```

⚠️ The last task sets the static IP — TrueNAS will then be reachable at `192.168.10.25`.

After completion, available:
- ZFS pool `data` (4x 3TB RAIDZ1) + pool `archive` (1x 6TB)
- Datasets: `data/media-data`, `data/downloads`, `data/backups`, `data/nextcloud`
- Zvols: `data/media-vm` (50GB), `data/media-config` (50GB)
- NFS shares on `192.168.10.0/24`
- TrueNAS media VM created — OS not yet installed

**Also run offsite backup setup:**
```bash
ansible-playbook truenas/cloudsync.yml
```
Note: requires Hetzner Storage Box credentials in `vars/secrets.yml` and SSH key `ssh/truenas-hetzner` to be present. Register the public key on the Hetzner Storage Box console first.

---

## Step 4 — Install Proxmox VE (nova, helix, vega)

> For each node individually.

1. Boot PVE ISO via **netboot.xyz** (PXE, DHCP Option 66/67 from Step 1)
   - Alternative: USB stick with PVE ISO
2. Install on **250GB NVMe** (OS disk)
3. After installation: WebUI at `https://<ip>:8006`
4. Add SSH key:
   ```bash
   ssh root@<ip> "mkdir -p /root/.ssh && echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK/8o2JjMARfA9ZTghcgksuK4tNU2POnQr0Tz5tMyqfS ansible@homelab' >> /root/.ssh/authorized_keys"
   ```
5. Join nodes to cluster (from the second node onwards):
   ```bash
   pvecm add 192.168.10.22  # nova is the first node
   ```
6. Configure 1TB NVMe as `local-lvm` datastore:
   - PVE WebUI → Datacenter → Storage → Add → LVM-Thin
   - Disk: `/dev/nvme0n1` (or similar — check with `lsblk`)
   - ID: `local-lvm`

---

## Step 5 — Build AlmaLinux Cloud-Init Template

> Once per PVE cluster. Template is cloned for all VMs.

```bash
# Run on a PVE node:
bash terraform/templates/alma9_cloudinit/build-template.sh
```

Template: ID `9000`, name `alma9-template-v1`, storage `local-lvm`

---

## Step 6 — Provision VMs via Terraform

```bash
cd terraform/proxmox
terraform init
terraform apply
```

Creates:
| VM | Node | IP |
|----|------|----|
| k3s-nova | nova | 192.168.10.10 |
| k3s-helix | helix | 192.168.10.11 |
| k3s-vega | vega | 192.168.10.12 |
| netboot | vega | 192.168.10.156 |
| dev | nova | 192.168.10.50 |

---

## Step 7 — Set up netboot.xyz

```bash
cd ansible
ansible-playbook vm_netboot.yml
```

Then reachable at: `http://192.168.10.156:3000` (web UI)

---

## Step 8 — Media VM: Install OS via ISO

> ⚠️ PXE boot does not work for TrueNAS VMs (iPXE EFI + initrd >100MB bug).
> Workaround: ISO install with Kickstart. Details: `ansible/roles/netboot_xyz/README.md`

1. Download AlmaLinux 9 ISO and attach to TrueNAS as CDROM device
2. TrueNAS WebUI → Virtualization → mediastack → Start → open console
3. GRUB menu → "Install AlmaLinux 9" → press `e`
4. Append to `linuxefi` line: `inst.ks=http://192.168.10.156:8080/almalinux-answers.ks`
5. `Ctrl+X` → installation runs fully automated
6. Remove CDROM device after installation
7. Base configuration via Ansible:
   ```bash
   ansible-playbook ansible/vm_base.yml -e target=mediastack
   ansible-playbook ansible/mediastack.yml
   ```

---

## Step 9 — Install k3s Cluster

> Prerequisite: Step 6 (VMs running), NFS via TrueNAS available (Step 3).

```bash
cd ansible

# Format + mount second disk (for Longhorn)
ansible-playbook k3s/prepare-disks.yml  # TODO: still to be created

# Install k3s
ansible-playbook k3s/install.yml        # TODO: still to be created
```

Internal order:
1. `k3s-nova` — first server (`--cluster-init`)
2. `k3s-helix` + `k3s-vega` — additional servers (`--server`)

---

## Step 10 — Kubernetes Bootstrap (GitOps)

```bash
# Make kubeconfig available locally
scp -i ssh/ansible ansible@192.168.10.10:/etc/rancher/k3s/k3s.yaml ~/.kube/config
# Adjust server IP in kubeconfig

# Deploy ArgoCD (once, manually)
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml -n argocd

# Apply root app → ArgoCD takes over everything else
kubectl apply -f k3s-manifests/bootstrap/root-app.yaml
```

ArgoCD then deploys automatically (App-of-Apps):
- cert-manager + Step-CA integration
- ingress-nginx
- Sealed Secrets ⚠️ Back up cluster key!
- NFS Subdir Provisioner
- Longhorn → backup target on `192.168.10.25:/mnt/data/backups`
- Authentik (SSO)
- All app services

---

## Disaster Recovery — Critical Data

| What | Where | How to restore |
|------|-------|----------------|
| **Infrastructure config** | this Git repo | `git clone` + runbook from the start |
| **ZFS data** | TrueNAS `data`/`archive` pools | rclone from Hetzner Storage Box |
| **k8s databases** | Longhorn backups → TrueNAS NFS → Hetzner | Longhorn UI → Restore |
| **Sealed Secrets key** | Back up to TrueNAS after initial installation | `kubectl get secret -n kube-system sealed-secrets-key -o yaml` → restore before apps |
| **Ansible secrets** | `ansible/truenas/vars/secrets.yml` (gitignored) | Restore manually from password manager |
| **Terraform credentials** | `terraform/proxmox/terraform.tfvars` (gitignored) | Regenerate manually from Proxmox |
