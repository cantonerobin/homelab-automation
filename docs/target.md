# Homelab — Ziel-Architektur

> Dieses File beschreibt den gewünschten Endzustand des Homelabs.
> Änderungen hier bedeuten: Roadmap (`roadmap.md`) muss angepasst werden.
> Letzte Aktualisierung: 2026-03-11

---

## Übersicht

```
┌─────────────────────────────────────────────────────┐
│  PVE Cluster (nova, helix, vega)                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │ k3s-nova │  │k3s-helix │  │ k3s-vega │  (VMs)  │
│  └──────────┘  └──────────┘  └──────────┘          │
│  ┌────────────────────────────────────────┐         │
│  │  Ceph Cluster (3x 1TB NVMe OSD)        │         │
│  └────────────────────────────────────────┘         │
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
- Ansible-konfiguriert (SSH, Ceph, PBS-Agent)
- Ceph-Cluster bleibt bestehen

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

| Dataset | Pfad | Genutzt von |
|---------|------|-------------|
| `media` | `/mnt/data/media` | Plex VM (direkt), k3s (NFS) |
| `downloads` | `/mnt/data/downloads` | Media VM (NFS) |
| `backups` | `/mnt/data/backups` | PBS VM |
| `nextcloud` | `/mnt/data/nextcloud` | k3s (NFS) |

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

### Kubernetes-Plattform

| Komponente | Tool | Zweck |
|-----------|------|-------|
| GitOps | ArgoCD (App-of-Apps) | Sync aus `k3s-manifests` Repo |
| Ingress | ingress-nginx | HTTP/HTTPS Routing |
| Zertifikate | cert-manager + Step-CA | Interne TLS-Certs |
| Storage | NFS Subdir Provisioner | PVCs auf TrueNAS NFS |
| Secrets | Sealed Secrets | Secret Management |
| Monitoring | Elastic Stack (ECK Operator) | Logs, Metrics, APM |
| SSO | Authentik | Single Sign-On für alle Services |

---

## Services — Endzustand

### k3s (via ArgoCD aus `k3s-manifests`)

| Service | Priorität | State | Notiz |
|---------|-----------|-------|-------|
| Cloudflare DynDNS | Hoch | Kein | |
| Homepage | Hoch | Kein | |
| Uptime Kuma | Hoch | Klein | |
| Gotify | Mittel | Klein | |
| Semaphore | Mittel | DB | ❓ Entscheidung offen — ggf. überflüssig wenn Ansible direkt via Git/CI läuft |
| Step-CA | Mittel | Kritisch | PKI-Migration sorgfältig planen |
| Authentik | Hoch | DB | Früh deployen, andere Services anbinden |
| Nextcloud | Niedrig | NFS + DB | ⚠️ Migrationsansatz noch offen — AIO nicht k3s-kompatibel, Entscheidung vor Phase 3 |
| Firefly III | Mittel | DB | |
| GitLab | Niedrig | DB | Erst nach Phase 3 stabil |
| Audiobookshelf | Mittel | NFS | Migration von Docker |
| Radarr | Mittel | NFS | Phase 1 + 3 Voraussetzung |
| Sonarr | Mittel | NFS | |
| Lidarr | Mittel | NFS | Musik-Downloads |
| Prowlarr | Mittel | Klein | |
| Seerr | Mittel | Klein | Overseerr-Fork |
| Tautulli | Mittel | Klein | Plex Statistiken |
| Wizarr | Niedrig | Klein | Plex Einladungs-Management |
| YTdl-Material | Niedrig | MongoDB | YouTube-DL Web-UI — MongoDB State |
| ECK Operator | Mittel | — | Elastic Stack Basis |
| Elasticsearch + Kibana | Mittel | ~4GB RAM | Ressourcenintensiv |
| Filebeat (DaemonSet) | Mittel | — | Log-Shipping |
| Metricbeat (DaemonSet) | Mittel | — | Metrics |
| APM Server | Niedrig | — | App Performance |

### PVE (dedizierte VMs, kein k3s)

| Service | VM | Begründung |
|---------|----|------------|
| HomeAssistant | Dedizierte PVE-VM | USB-Passthrough (Zigbee-Stick) |
| PBS | TrueNAS KVM-VM | Storage-Nähe |
| Plex | TrueNAS KVM-VM | Hardware-Transcoding, Storage-Nähe |
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
apps/core/                  # cert-manager, ingress-nginx, sealed-secrets
apps/media/                 # Radarr, Sonarr, Prowlarr, Overseerr (Plex bleibt auf TrueNAS VM)
apps/monitoring/            # Uptime Kuma, ECK, Kibana
apps/services/              # Homepage, Gotify, DynDNS, Semaphore (⚠️ Semaphore ggf. nicht mehr nötig)
apps/auth/                  # Authentik
apps/argocd/                # ArgoCD self-managed
docs/
```

---

## Architektur-Entscheidungen

| Thema | Entscheidung | Begründung |
|-------|-------------|------------|
| GitOps | ArgoCD (App-of-Apps Pattern) | Standard, gut dokumentiert |
| HomeAssistant | Dedizierte PVE-VM | USB-Passthrough (Zigbee-Stick) nicht in k3s möglich |
| GitLab | GitLab.com → later self-hosted | k3s muss erst stabil sein |
| Secret Management | Sealed Secrets → später evtl. Vault | Einfacher Einstieg |
| Monitoring | Elastic Stack (ECK) | Robin ist Elastic-zertifiziert |
| NZBGet | TrueNAS VM dauerhaft | Performance — kein NFS-Overhead |
| k3s PVC Storage | ⚠️ Offen | NFS only vs. Hybrid (NFS + Longhorn für DBs) → PoC POC-3/4 |
| PVE Reinstall | ⚠️ Offen | netboot.xyz noch nicht definitiv → PoC POC-1 |
| k3s statische IPs | Cloud-Init in Terraform | Flexibler als Unifi DHCP-Reservierung |
| k3s HA | 3 Server-Nodes (embedded etcd) | Kein SPOF auf Control Plane — alle Nodes gleichwertig |
| Semaphore | ❓ Offen | Wenn Ansible nur noch via Git ausgeführt wird → nicht mehr nötig |
| Nextcloud Migration | ❓ Offen | AIO nicht k3s-kompatibel → Entscheidung: AIO auf VM behalten oder auf Standard-Stack migrieren |
| NPM → ingress-nginx | ❓ Cutover-Plan noch zu definieren | Koordinierter Wechsel aller DNS/Cloudflare-Einträge nötig |
| Network Source of Truth | Pure IaC (variables.tf, hosts.yml) | Netbox optional als Visualisierung wenn k3s stabil |
| Netzwerk-Doku | `docs/current.md` / `docs/target.md` + IaC | Kein Netbox als Dependency |
