# Homelab — Rebuild Runbook

> Schritt-für-Schritt Anleitung um die gesamte Infrastruktur von Null aufzubauen.
> Reihenfolge ist zwingend — spätere Schritte haben Abhängigkeiten auf frühere.
> Letzte Aktualisierung: 2026-03-14

---

## Voraussetzungen (einmalig, lokal)

```bash
# SSH-Keypair liegt in ssh/ansible (gitignored) + ssh/ansible.pub (committed)
# Falls neu generieren:
ssh-keygen -t ed25519 -C "ansible@homelab" -f ssh/ansible

# Terraform
terraform -version  # >= 1.0

# Ansible
ansible --version   # >= 2.14
ansible-galaxy collection install -r ansible/requirements.yml

# terraform.tfvars anlegen (gitignored)
cp terraform/proxmox/terraform.tfvars.example terraform/proxmox/terraform.tfvars
# → pm_api_url, pm_api_token_id, pm_api_token_secret eintragen
```

---

## Schritt 1 — Netzwerk (Unifi)

> Einmalig konfiguriert, sollte persistieren. Nur relevant bei komplettem Unifi-Reset.

- VLANs anlegen: 2 (Mgmt), 10 (Server), 20 (Client), 30 (DMZ), 40 (Untrust)
- Trunk-Ports auf Switch-Ports der PVE-Nodes konfigurieren (alle VLANs tagged)
- DHCP Option 66/67 auf VLAN 10 → `192.168.10.156` (netboot.xyz, für PXE-Boot)
- Statische IPs / DHCP-Reservierungen:

| Host | IP |
|------|----|
| helix | 192.168.10.20 |
| vega | 192.168.10.21 |
| nova | 192.168.10.22 |
| orion (TrueNAS) | 192.168.10.25 |

---

## Schritt 2 — TrueNAS Scale installieren (orion)

1. TrueNAS Scale ISO booten (USB oder netboot.xyz)
2. Installation auf **2x 250GB SATA SSD** (Mirror) — alle anderen Disks NICHT anfassen
3. Nach Installation: WebUI unter `http://<DHCP-IP>` aufrufen
4. **SSH aktivieren:** System → Services → SSH → Start + Enable
5. **Ansible SSH-Key hinterlegen:**
   - System → Shell oder direkt via WebUI-Terminal:
   ```bash
   mkdir -p /root/.ssh
   echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK/8o2JjMARfA9ZTghcgksuK4tNU2POnQr0Tz5tMyqfS ansible@homelab" >> /root/.ssh/authorized_keys
   chmod 600 /root/.ssh/authorized_keys
   ```
6. Verbindung testen:
   ```bash
   ssh -i ssh/ansible root@<ip>
   ```

---

## Schritt 3 — TrueNAS via Ansible konfigurieren

> Konfiguriert: ZFS Pools, Datasets, Zvols, NFS, Snapshots, Scrubs, VMs, Netzwerk.
> Voraussetzung: Schritt 2 abgeschlossen, Disks physisch eingebaut (4x 3TB + 1x 6TB).

```bash
# IP in vars/config.yml temporär auf aktuelle DHCP-IP anpassen falls nötig
# ansible/truenas/vars/config.yml → truenas_ip

cd ansible
ansible-playbook truenas/configure.yml
```

⚠️ Der letzte Task setzt die statische IP — danach ist TrueNAS unter `192.168.10.25` erreichbar.

Nach Abschluss verfügbar:
- ZFS Pool `data` (4x 3TB RAIDZ1) + Pool `archive` (1x 6TB)
- Datasets: `data/media-data`, `data/downloads`, `data/backups`, `data/nextcloud`, `archive/pbs`
- Zvols: `data/pbs-vm` (32GB), `data/media-vm` (50GB), `data/media-config` (50GB)
- NFS-Shares auf `192.168.10.0/24`
- TrueNAS VMs angelegt (PBS + Media) — OS noch nicht installiert

---

## Schritt 4 — Proxmox VE installieren (nova, helix, vega)

> Für jeden Node einzeln. Reihenfolge: nova → helix → vega.

1. PVE ISO via **netboot.xyz** booten (PXE, DHCP Option 66/67 aus Schritt 1)
   - Alternativ: USB-Stick mit PVE ISO
2. Installation auf **250GB NVMe** (OS-Disk)
3. Nach Installation: WebUI unter `https://<ip>:8006`
4. SSH-Key hinterlegen:
   ```bash
   ssh root@<ip> "mkdir -p /root/.ssh && echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK/8o2JjMARfA9ZTghcgksuK4tNU2POnQr0Tz5tMyqfS ansible@homelab' >> /root/.ssh/authorized_keys"
   ```
5. Nodes zum Cluster joinen (vom zweiten Node an):
   ```bash
   pvecm add 192.168.10.22  # nova ist erster Node
   ```
6. 1TB NVMe als `local-lvm` Datastore konfigurieren:
   - PVE WebUI → Datacenter → Storage → Add → LVM-Thin
   - Disk: `/dev/nvme0n1` (oder ähnlich — prüfen mit `lsblk`)
   - ID: `local-lvm`

---

## Schritt 5 — AlmaLinux Cloud-Init Template bauen

> Einmalig pro PVE-Cluster. Template wird für alle VMs geklont.

```bash
# Auf einem PVE-Node ausführen:
bash terraform/templates/alma9_cloudinit/build-template.sh
```

Template: ID `9000`, Name `alma9-template-v1`, Storage `local-lvm`

---

## Schritt 6 — VMs via Terraform provisionieren

```bash
cd terraform/proxmox
terraform init
terraform apply
```

Erstellt:
| VM | Node | IP |
|----|------|----|
| k3s-nova | nova | 192.168.10.10 |
| k3s-helix | helix | 192.168.10.11 |
| k3s-vega | vega | 192.168.10.12 |
| netboot | vega | 192.168.10.156 |
| dev | nova | 192.168.10.50 |

---

## Schritt 7 — netboot.xyz einrichten

```bash
cd ansible
ansible-playbook vm_netboot.yml
```

Danach erreichbar: `http://192.168.10.156:3000` (Web UI)

---

## Schritt 8 — TrueNAS VMs: OS via PXE installieren

> PBS und Media VM booten via netboot.xyz. Voraussetzung: Schritt 7 abgeschlossen.

**PBS VM (Debian):**
1. TrueNAS WebUI → Virtualization → pbs → Start
2. In TrueNAS Shell: `midclt call vm.get_console <id>` — oder via WebUI-Console
3. PXE-Boot → netboot.xyz → Debian Installer
4. Partitionierung: gesamte Disk (`/dev/sda`, 32GB), kein Swap
5. Nach Installation: PBS installieren:
   ```bash
   echo "deb http://download.proxmox.com/debian/pbs bookworm pbs-no-subscription" > /etc/apt/sources.list.d/pbs.list
   wget -qO- https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg | apt-key add -
   apt update && apt install -y proxmox-backup-server
   ```
6. SSH-Key hinterlegen (root):
   ```bash
   mkdir -p /root/.ssh
   echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK/8o2JjMARfA9ZTghcgksuK4tNU2POnQr0Tz5tMyqfS ansible@homelab" >> /root/.ssh/authorized_keys
   ```

**Media VM (AlmaLinux):**
1. TrueNAS WebUI → Virtualization → media → Start
2. PXE-Boot → netboot.xyz → AlmaLinux 9 Installer
3. Partitionierung: `/dev/sda` (50GB OS), `/dev/sdb` wird `/opt/media-stack` (50GB Config)
4. Nach Installation: `/dev/sdb` formatieren + mounten:
   ```bash
   mkfs.xfs /dev/sdb
   mkdir -p /opt/media-stack
   echo "/dev/sdb /opt/media-stack xfs defaults 0 0" >> /etc/fstab
   mount -a
   ```
5. SSH-Key hinterlegen (root)

---

## Schritt 9 — k3s Cluster installieren

> Voraussetzung: Schritt 6 (VMs laufen), NFS via TrueNAS verfügbar (Schritt 3).

```bash
cd ansible

# Zweite Disk formatieren + mounten (für Longhorn)
ansible-playbook k3s/prepare-disks.yml  # TODO: noch zu erstellen

# k3s installieren
ansible-playbook k3s/install.yml        # TODO: noch zu erstellen
```

Reihenfolge intern:
1. `k3s-nova` — erster Server (`--cluster-init`)
2. `k3s-helix` + `k3s-vega` — weitere Server (`--server`)

---

## Schritt 10 — Kubernetes Bootstrap (GitOps)

```bash
# kubeconfig lokal verfügbar machen
scp -i ssh/ansible ansible@192.168.10.10:/etc/rancher/k3s/k3s.yaml ~/.kube/config
# Server-IP in kubeconfig anpassen

# ArgoCD deployen (einmalig manuell)
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml -n argocd

# Root-App applyen → ArgoCD übernimmt alles weitere
kubectl apply -f k3s-manifests/bootstrap/root-app.yaml
```

ArgoCD deployed dann automatisch (App-of-Apps):
- cert-manager + Step-CA Integration
- ingress-nginx
- Sealed Secrets ⚠️ Cluster-Key sichern!
- NFS Subdir Provisioner
- Longhorn → Backup Target auf `192.168.10.25:/mnt/data/backups`
- Authentik (SSO)
- Alle App-Services

---

## Disaster Recovery — kritische Daten

| Was | Wo | Wie wiederherstellen |
|-----|----|--------------------|
| **Infrastruktur-Config** | dieses Git-Repo | `git clone` + Runbook von vorn |
| **ZFS Daten** | TrueNAS `data`/`archive` Pools | Rclone von Hetzner Storage Box |
| **VM-Backups** | PBS auf TrueNAS (`archive/pbs`) | PBS WebUI → Restore |
| **k8s Datenbanken** | Longhorn Backups → TrueNAS NFS → Hetzner | Longhorn UI → Restore |
| **Sealed Secrets Key** | PBS / TrueNAS sichern nach Erstinstallation | `kubectl get secret -n kube-system sealed-secrets-key -o yaml` → restore vor Apps |
| **Ansible Secrets** | `ansible/truenas/vars/secrets.yml` (gitignored) | Manuell wiederherstellen aus Passwort-Manager |
| **Terraform Credentials** | `terraform/proxmox/terraform.tfvars` (gitignored) | Manuell aus Proxmox neu generieren |

---

## SSH Public Key (zur Referenz)

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK/8o2JjMARfA9ZTghcgksuK4tNU2POnQr0Tz5tMyqfS ansible@homelab
```

Auch in `ssh/ansible.pub` im Repo.
