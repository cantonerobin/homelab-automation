# Homelab — Ist-Zustand

> Dieses File beschreibt den aktuellen Stand der Infrastruktur.
> Letzte Aktualisierung: 2026-03-15

---

## Hardware

### TrueNAS Scale "orion" (192.168.10.25)
- CPU: Ryzen 7 3700X, 64GB RAM
- OS-Disks: 2x 250GB SATA SSD (Mirror)
- ZFS Pool `data`: 4x 3TB HDD RAIDZ1 (~9TB nutzbar)
- ZFS Pool `archive`: 1x 6TB HDD (Standalone)
- L2ARC: 1x 1TB SATA SSD (❌ noch nicht konfiguriert)
- VM-Storage: 1x 2TB SATA SSD (Zvols für PBS + Media VM)
- GPU (installiert): NVIDIA GTX 970 4GB (PCIe) — für Plex HW-Transcoding (P1-15)
- GPU (geplant): NVIDIA GTX 1060 6GB — für AI-VM (B-42, noch nicht eingebaut)

### PVE Nodes nova / helix / vega (bleiben PVE)
- CPU: Intel i5-8500T, 16GB RAM
- Disks: 1x 250GB NVMe (OS), 1x 1TB NVMe (Ceph OSD)
- Ceph-Cluster läuft auf diesen 3 Nodes

### Synology NAS
- ⚠️ Disks ausgebaut → in TrueNAS eingebaut
- Gerät leer / nicht mehr in Betrieb

### Raspberry Pi (2x Pi 4)

| Pi | Rolle | Status |
|----|-------|--------|
| Pi 1 | AdGuard Home Primary DNS | ❌ noch nicht konfiguriert |
| Pi 2 | AdGuard Home Secondary DNS | ❌ noch nicht konfiguriert |

- Bewusst außerhalb von k3s — DNS ist kritische Infrastruktur
- AdGuard Home Sync zwischen beiden Instanzen geplant
- Beide IPs werden als DNS-Server im Router/DHCP eingetragen

---

## Netzwerk

### VLAN-Schema

| VLAN | Subnetz | Name | Inhalt |
|------|---------|------|--------|
| 2 | 192.168.1.0/24 | Management | Firewall, Switches, APs, PVE-Nodes |
| 10 | 192.168.10.0/24 | Server | PVE-Nodes, k3s VMs + Services, TrueNAS |
| 20 | 192.168.20.0/24 | Client | Endpoints |
| 30 | 192.168.30.0/24 | DMZ | Extern exponierte Services |
| 40 | 192.168.40.0/24 | Untrust | WLAN, IoT |

- Trunk-Ports auf PVE-Nodes und Unifi konfiguriert ✅ — alle VLANs freigegeben
- DHCP Option 66/67 für netboot.xyz konfiguriert ✅

### Node-IPs (statisch, VLAN 10)

| Host | IP | DNS |
|------|----|-----|
| helix | 192.168.10.20 | helix.cantone.net |
| vega | 192.168.10.21 | vega.cantone.net |
| nova | 192.168.10.22 | nova.cantone.net |
| orion (TrueNAS) | 192.168.10.25 | truenas.cantone.net |

---

## TrueNAS Scale (orion, 192.168.10.25)

> Konfiguriert via `ansible/truenas/configure.yml`

### ZFS Pools

| Pool | Disks | RAID | Zweck |
|------|-------|------|-------|
| `data` | 4x 3TB HDD | RAIDZ1 | Media, Downloads, Nextcloud, Backups, VM-Zvols |
| `archive` | 1x 6TB HDD | Stripe | Cold Storage / PBS Backups |

### Datasets (`data` Pool)

| Dataset | Zweck |
|---------|-------|
| `data/media-data` | Plex-Mediathek |
| `data/downloads` | NZBGet Downloads |
| `data/backups` | Backups (Longhorn Backup Target) |
| `data/nextcloud` | Nextcloud-Daten |

### Zvols (VM-Disks)

| Zvol | Größe | VM |
|------|-------|----|
| `data/pbs-vm` | 32GB | PBS OS-Disk |
| `data/media-vm` | 50GB | Media VM OS-Disk |
| `data/media-config` | 50GB | Media VM Config-Disk (`/opt/mediastack`) |

### Datasets (`archive` Pool)

| Dataset | Zweck |
|---------|-------|
| `archive/pbs` | PBS Backup-Storage |

### NFS-Shares

| Pfad | Netz | Zweck |
|------|------|-------|
| `/mnt/data/media-data` | 192.168.10.0/24 | Plex-Mediathek |
| `/mnt/data/downloads` | 192.168.10.0/24 | Download-Verzeichnis |
| `/mnt/data/nextcloud` | 192.168.10.0/24 | Nextcloud-Daten |
| `/mnt/data/backups` | 192.168.10.0/24 | Longhorn Backup Target |

### TrueNAS VMs

| VM | vCPUs | RAM | Disk | GPU | Status |
|----|-------|-----|------|-----|--------|
| pbs | 4 | 8GB | 32GB (data/pbs-vm) | — | ✅ Angelegt — ❌ OS noch nicht installiert |
| mediastack | 4 | 16GB | 50GB OS + 50GB Config | GTX 970 (P1-15) | ✅ Angelegt — ❌ OS noch nicht installiert |

---

## Virtuelle Maschinen (Terraform-verwaltet, PVE)

| VM | Node | IP | VLAN | Status |
|----|------|----|------|--------|
| k3s-nova | nova | 192.168.10.10 | 10 | ✅ läuft |
| k3s-helix | helix | 192.168.10.11 | 10 | ✅ läuft |
| k3s-vega | vega | 192.168.10.12 | 10 | ✅ läuft |
| netboot | vega | 192.168.10.156 | 10 | ✅ läuft — hostet netboot.xyz |
| dev | nova | 192.168.10.61 | 10 | ✅ läuft — HomeAssistant Dev |

- Template: `alma9-template-v1` (AlmaLinux 9 Cloud-Init, ID 9000)
- Terraform Provider: `telmate/proxmox 3.0.2-rc07`
- Storage: `ceph_data`

---

## Services (LXC-basiert)

> Standard-Pattern: LXC + Docker darin. Ausnahme: grosse Services laufen in einer VM.
> LXC-Node-Zuordnung irrelevant — Storage auf Ceph, LXCs jederzeit migrierbar.
> DNS-Schema: intern = `<service>.cantone.net`, extern (Cloudflare) = eigener Name → Redirect auf intern.

### LXC-Services (auf PVE)

| Service | IP | Interner DNS | Port | Notiz |
|---------|----|-------------|------|-------|
| Nginx Proxy Manager | 192.168.10.75 | proxy.cantone.net | 80, 443, 81 (Admin) | Docker in LXC — MariaDB |
| Step-CA | 192.168.10.56 | step-ca.cantone.net | 9000 | Docker in LXC — ACME aktiviert |
| Gotify | 192.168.10.52 | gotify.cantone.net | 443 (via NPM) | Docker in LXC |
| Homepage | 192.168.10.93 | homepage.cantone.net | 3000 | Docker in LXC — extern: dash.cantone.net |
| Cloudflare DynDNS | 192.168.10.78 | cloudflare-ddns.cantone.net | — | Docker in LXC — wildcard *.cantone.net |
| Uptime Kuma | 192.168.10.91 | monitor.cantone.net | 3001 (via NPM) | Docker in LXC |
| Nextcloud | 192.168.10.82 | nextcloud.cantone.net | 11000 (via NPM) | Nextcloud AIO |

### VMs (nicht Terraform-verwaltet)

| Service | IP | DNS | Port | Notiz |
|---------|----|-----|------|-------|
| HomeAssistant | 192.168.10.61 | homeassistant.cantone.net | 8123 (via NPM) | Dev-VM — Prod mit USB-Passthrough ausstehend |

### Media-Stack (Docker Compose auf Media-VM, läuft auf orion)

Config: `docs/legacy/docker-compose/mediastack.yml`

| Service | Port | Notiz |
|---------|------|-------|
| Plex | 32400 | HW-Transcoding via `/dev/dri` (Intel QuickSync) |
| NZBGet | 6789 | Usenet Downloader |
| Radarr | 7878 | Filme |
| Sonarr | 8989 | Serien |
| Lidarr | 8686 | Musik |
| Prowlarr | 9696 | Indexer-Management |
| Seerr | 5055 | Overseerr-Fork (Request-Management) |
| Tautulli | 8181 | Plex Statistiken |
| Wizarr | 5690 | Plex Einladungs-Management |
| Audiobookshelf | 13378 | Hörbücher + Podcasts |
| YTdl-Material | 8998 | YouTube-DL Web-UI (yt-dlp, mit MongoDB) |

---

## Ceph

- Cluster läuft auf nova, helix, vega (je 1x 1TB **NVMe** als OSD) — **3 OSDs** (orion bereits entfernt)
- k3s VM-Disks und LXC-Storage liegen auf `ceph_data`
- ⚠️ Ceph wird in Phase 2 entfernt → 1TB NVMe pro Node wird local-lvm

---

## Security-Status

| Thema | Status |
|-------|--------|
| SSH-Private-Key aus Git-History entfernen | ✅ Erledigt (git filter-repo) |
| Neues SSH-Keypair für Ansible generieren | ✅ Erledigt |
| `cipassword` in Cloud-Init Template | ✅ Entfernt — nur SSH-Key Auth |
| `terraform.tfvars` (API-Credentials) | ✅ in `.gitignore` |
