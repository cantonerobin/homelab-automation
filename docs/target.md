# Homelab — Ziel-Architektur

> Dieses File beschreibt den gewünschten Endzustand des Homelabs.
> Änderungen hier bedeuten: Roadmap (`roadmap.md`) muss angepasst werden.
> Letzte Aktualisierung: 2026-03-12

---

## Übersicht

```
┌─────────────────────────────────────────────────────┐
│  PVE Cluster (nova, helix, vega)                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │ k3s-nova │  │k3s-helix │  │ k3s-vega │  (VMs)  │
│  └──────────┘  └──────────┘  └──────────┘          │
│  Storage: local-lvm (1TB NVMe/Node, nach Phase 2)   │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  TrueNAS Scale (orion)                              │
│  ZFS data (4x3TB RAIDZ1) + archive (1x6TB)         │
│  ┌──────────────┐  ┌──────────────────────┐        │
│  │  PBS VM      │  │  Media VM            │        │
│  │  (Backup)    │  │  (Plex + NZBGet)     │        │
│  └──────────────┘  └──────────────────────┘        │
└─────────────────────────────────────────────────────┘
```

---

## Hardware (Endzustand)

### TrueNAS Node "orion"
- CPU: Ryzen 7 3700X, 64GB RAM
- OS: TrueNAS Scale (auf 2x 250GB SATA SSD Mirror)
- L2ARC: 1x 1TB SATA SSD
- VM-Storage: 1x 2TB SATA SSD

### PVE Nodes nova / helix / vega
- Neu installiert (Phase 2, rolling)
- Ansible-konfiguriert (SSH, PBS-Agent)
- Storage: 1x 250GB NVMe (OS), 1x 1TB NVMe (local-lvm Datastore — ersetzt Ceph OSD)

---

## Netzwerk

VLAN-Schema bleibt unverändert. Änderungen gegenüber Ist-Zustand:

| VLAN | Subnetz | Name | Inhalt |
|------|---------|------|--------|
| 2 | 192.168.1.0/24 | Management | Firewall, Switches, APs, PVE-Nodes, TrueNAS |
| 10 | 192.168.10.0/24 | Server | k3s VMs + Services |
| 20 | 192.168.20.0/24 | Client | Endpoints |
| 30 | 192.168.30.0/24 | DMZ | Extern exponierte Services |
| 40 | 192.168.40.0/24 | Untrust | WLAN, IoT |

- **orion (TrueNAS):** zieht sich aus VLAN 10 zurück → nur noch Management (VLAN 2)
- **Synology:** fällt weg (Disks → TrueNAS)
- **k3s VMs:** bleiben statisch in VLAN 10 (192.168.10.10–.12)
- **PVE-Nodes nova/helix/vega:** IPs unverändert

---

## ZFS Pool Design (TrueNAS)

| Pool | Disks | RAID | Nutzbar | Zweck |
|------|-------|------|---------|-------|
| `data` | 4x 3TB (ex-Synology) | RAIDZ1 | ~9TB | Media, Nextcloud, Backups |
| `archive` | 1x 6TB (ex-Synology) | Standalone | ~6TB | Cold Storage / PBS Backups |
| OS Boot | 2x 250GB SATA SSD | Mirror | — | TrueNAS OS |
| L2ARC | 1x 1TB SATA SSD | — | — | Read Cache |
| VM-Disks | 1x 2TB SATA SSD | — | — | PBS VM + Media VM |

> Konfiguration via Ansible gegen TrueNAS REST API (`/api/v2.0`) — Pools, Datasets, NFS Shares, Snapshot-Tasks. Disk-Identifier als Variablen in `ansible/truenas/`. Playbook wird zuerst gegen Test-VM validiert.

### Datasets (auf `data` Pool)

| Dataset | Pfad | Recordsize | Compression | Genutzt von |
|---------|------|------------|-------------|-------------|
| `media` | `/mnt/data/media` | 1M | LZ4 | Plex VM (direkt), k3s (NFS) |
| `downloads` | `/mnt/data/downloads` | 128k | LZ4 | Media VM (NFS) |
| `backups` | `/mnt/data/backups` | 128k | ZSTD | PBS VM |
| `backups/longhorn` | `/mnt/data/backups/longhorn` | 128k | ZSTD | Longhorn Backup Target (k3s) |
| `nextcloud` | `/mnt/data/nextcloud` | 16k | LZ4 | k3s (NFS) |

---

## VMs auf TrueNAS (KVM)

| VM | CPU | RAM | Disk | Zweck |
|----|-----|-----|------|-------|
| pbs | 4 cores | 8GB | 32GB (auf 2TB SSD) | Proxmox Backup Server |
| media | 4 cores | 16GB | 50GB (auf 2TB SSD) | Plex + NZBGet |

---

## k3s Cluster

- 3 Nodes: **alle Server-Nodes** (HA, embedded etcd) — kein dedizierter Agent
- IPs: 192.168.10.10 / .11 / .12, VLAN 10, Gateway 192.168.10.1
- Terraform-provisioniert (AlmaLinux 9 Cloud-Init)
- Ansible-konfiguriert (k3s-Installation + Updates)
- Init: k3s-nova mit `--cluster-init`, helix + vega joinen via `--server`

### VM-Disk-Layout pro k3s Node

| Disk | Grösse | Zweck |
|------|--------|-------|
| Root-Disk (virtio) | 40GB | OS, k3s Binaries, Container Images |
| Longhorn-Disk (virtio) | 100GB | `/var/lib/longhorn` — dediziert für Longhorn Storage |

### Kubernetes-Plattform

| Komponente | Tool | Zweck |
|-----------|------|-------|
| GitOps | ArgoCD (App-of-Apps) | Sync aus `k3s-manifests` Repo |
| Ingress | ingress-nginx | HTTP/HTTPS Routing |
| Zertifikate | cert-manager + Step-CA | Interne TLS-Certs |
| Storage (Shared) | NFS Subdir Provisioner | RWX PVCs auf TrueNAS NFS (Media, Nextcloud) |
| Storage (Stateful) | Longhorn | RWO PVCs für DBs + stateful Apps, repliziert über 3 Nodes |
| Secrets | Sealed Secrets | kubeseal-verschlüsselt, in Git committed — Cluster-Key sichern! |
| SSO | Authentik | Single Sign-On für App-Services |
| Monitoring | ❓ Nach Phase 3 evaluieren | Kandidat: Grafana + Prometheus |

---

## Disaster Recovery

| Schicht | Was | Wo | Offsite |
|---------|-----|----|---------|
| Daten | TrueNAS `data` Pool | Hetzner Storage Box via Rclone (Cloud Sync) | ✅ |
| Datenbanken | Longhorn Backups | TrueNAS NFS (`backups/longhorn`) → via Rclone mitgenommen | ✅ |
| VMs | PBS Backups | TrueNAS lokal (`backups`) | ❌ vorerst |
| Konfiguration | Git | GitLab.com Push Mirror | ✅ |

**Bei totalem Hardwareverlust:** PBS VM-Backups nicht wiederherstellbar. Infrastruktur kann aber via Git + Terraform + Ansible neu aufgebaut werden, Daten via Hetzner Storage Box zurückgespielt werden.

---

## Services — Endzustand

### k3s (via ArgoCD aus `k3s-manifests`)

| Service | Priorität | State | Authentik |
|---------|-----------|-------|-----------|
| Cloudflare DynDNS | Hoch | Kein | ✗ |
| Homepage | Hoch | Kein | ✓ |
| Uptime Kuma | Hoch | Klein | ✓ |
| Gotify | Mittel | Klein | ✗ (intern) |
| Step-CA | Mittel | Kritisch | ✗ (Infra) |
| Authentik | Hoch | DB (Longhorn) | — (ist der SSO-Provider) |
| Nextcloud | Mittel | NFS + DB (Longhorn) | ✓ |
| Firefly III | Mittel | DB (Longhorn) | ✓ |
| GitLab | Niedrig | DB (Longhorn) | ✓ |
| Audiobookshelf | Mittel | NFS | ✓ |
| Radarr | Mittel | NFS | ✓ |
| Sonarr | Mittel | NFS | ✓ |
| Lidarr | Mittel | NFS | ✓ |
| Prowlarr | Mittel | Klein | ✓ |
| Seerr | Mittel | Klein | ✓ |
| Tautulli | Mittel | Klein | ✓ |
| Wizarr | Niedrig | Klein | ✗ (Plex-intern) |
| YTdl-Material | Niedrig | MongoDB (Longhorn) | ✓ |

### PVE (dedizierte VMs, kein k3s)

| Service | VM | Begründung |
|---------|----|------------|
| HomeAssistant | Dedizierte PVE-VM | USB-Passthrough (Zigbee-Stick) nicht in k3s möglich |
| PBS | TrueNAS KVM-VM | Storage-Nähe |
| Plex | TrueNAS KVM-VM | HW-Transcoding via GPU-Passthrough (dedizierte GPU in orion, unter PVE durch Display-Output blockiert, unter TrueNAS frei) |
| NZBGet | TrueNAS KVM-VM | Performance (kein NFS-Overhead) |

> **Migrations-Strategie Media-Stack:** Alle Services laufen nach Phase 1 auf TrueNAS Media VM weiter. Nach Phase 3 (k3s stabil) werden Services einzeln nach k3s migriert — minimale Downtime pro Service, da externe User betroffen.

---

## Git Repositories

### `homelab-automation` (dieses Repo)
```
terraform/proxmox/    # VM-Provisioning
ansible/proxmox/      # PVE-Node-Konfiguration
ansible/truenas/      # ZFS-Pools, NFS-Shares, Datasets
ansible/k3s/          # k3s Bootstrap + Node-Config
docs/
```

### `k3s-manifests` (noch zu erstellen)
```
bootstrap/root-app.yaml     # einmalig manuell applyen
apps/core/                  # cert-manager, ingress-nginx, sealed-secrets, longhorn, nfs-provisioner
apps/auth/                  # Authentik
apps/media/                 # Radarr, Sonarr, Lidarr, Prowlarr, Seerr, Tautulli, Wizarr, Audiobookshelf, YTdl-Material
apps/services/              # Homepage, Gotify, DynDNS, Uptime Kuma, Nextcloud, Firefly III, GitLab
apps/monitoring/            # Grafana + Prometheus (nach Phase 3 evaluieren)
apps/argocd/                # ArgoCD self-managed
docs/
```

---

## Architektur-Entscheidungen

| Thema | Entscheidung | Begründung |
|-------|-------------|------------|
| GitOps | ArgoCD (App-of-Apps Pattern) | Standard, gut dokumentiert |
| HomeAssistant | Dedizierte PVE-VM | USB-Passthrough (Zigbee-Stick) nicht in k3s möglich |
| GitLab | GitHub Übergang → self-hosted nach Phase 3, Push Mirror zu GitLab.com | Offsite-Backup, spätere Source of Truth |
| Secret Management | Sealed Secrets | kubeseal lokal, SealedSecret in Git committed. Cluster-Key muss gesichert werden (PBS/TrueNAS) |
| Monitoring | ❓ Offen — nach Phase 3 evaluieren | Elastic Stack gestrichen (zu ressourcenintensiv). Kandidat: Grafana + Prometheus |
| NZBGet | TrueNAS VM dauerhaft | Performance — kein NFS-Overhead |
| k3s PVC Storage | Hybrid: Longhorn (RWO/DBs) + NFS (RWX/Media/Nextcloud) | Longhorn für Replikation + Backup, NFS für shared large files |
| k3s Longhorn Disk | 2 virtio-Disks pro VM: Root 40GB + Longhorn 100GB | IO-Trennung OS/Replikation, unabhängig resizebar |
| PVE Storage | local-lvm (nach Phase 2, Ceph entfernt) | Ceph zu komplex für 3-Node-Setup ohne dedizierte Ceph-Nodes |
| PVE Reinstall | netboot.xyz | PoC POC-1 vor Phase 2 |
| k3s statische IPs | Cloud-Init in Terraform | Flexibler als Unifi DHCP-Reservierung |
| k3s HA | 3 Server-Nodes (embedded etcd) | Kein SPOF auf Control Plane — alle Nodes gleichwertig |
| Semaphore | Gestrichen | Ansible direkt via CLI oder CI |
| Authentik | Früh deployen, alle App-Services | NICHT für Infra-Tools (Proxmox, TrueNAS, ArgoCD, Longhorn) — nur via VPN erreichbar |
| Nextcloud | Zweistufig: AIO auf TrueNAS VM → PoC → Migration zu k3s | Sanfte Migration, Daten bleiben auf bestehendem NFS Dataset |
| NPM → ingress-nginx | ❓ Cutover-Plan noch zu definieren | Koordinierter Wechsel aller DNS/Cloudflare-Einträge nötig |
| Network Source of Truth | Pure IaC (variables.tf, hosts.yml) | Netbox optional als Visualisierung wenn k3s stabil |
