# Homelab — Ist-Zustand

> Dieses File beschreibt den aktuellen Stand der Infrastruktur.
> Letzte Aktualisierung: 2026-03-11

---

## Hardware

### PVE Node "orion" (→ wird TrueNAS, Phase 1)
- CPU: Ryzen 7 3700X, 64GB RAM
- Disks: 2x 250GB SATA SSD, 1x 1TB SATA SSD, 1x 2TB SATA SSD
- Erhält Synology-Disks: 1x 6TB HDD, 4x 3TB HDD
- Aktuell Ceph-Member ⚠️ → muss vor Shutdown sauber evakuiert werden

### PVE Nodes nova / helix / vega (bleiben PVE)
- CPU: Intel i5-8500T, 16GB RAM
- Disks: 1x 250GB NVMe (OS), 1x 1TB NVMe (Ceph OSD)
- Ceph-Cluster läuft auf diesen 3 Nodes

### Synology NAS
- Disks: 1x 6TB HDD, 4x 3TB HDD
- Alle Disks werden zu TrueNAS migriert (Phase 1)

---

## Netzwerk

### VLAN-Schema

| VLAN | Subnetz | Name | Inhalt |
|------|---------|------|--------|
| 2 | 192.168.1.0/24 | Management | Firewall, Switches, APs, PVE-Nodes |
| 10 | 192.168.10.0/24 | Server | PVE-Nodes, k3s VMs + Services, Synology |
| 20 | 192.168.20.0/24 | Client | Endpoints |
| 30 | 192.168.30.0/24 | DMZ | Extern exponierte Services |
| 40 | 192.168.40.0/24 | Untrust | WLAN, IoT |

- Trunk-Ports auf PVE-Nodes und Unifi konfiguriert ✅ — alle VLANs freigegeben

### Node-IPs (statisch, VLAN 10)

| Host | IP | DNS |
|------|----|-----|
| helix | 192.168.10.20 | helix.cantone.net |
| vega | 192.168.10.21 | vega.cantone.net |
| nova | 192.168.10.22 | nova.cantone.net |
| orion | 192.168.10.25 | orion.cantone.net |
| nas01 (Synology) | 192.168.10.100 | — |

---

## Virtuelle Maschinen (Terraform-verwaltet)

| VM | Node | IP | VLAN | Status |
|----|------|----|------|--------|
| k3s-nova | nova | 192.168.10.10 | 10 | ✅ läuft |
| k3s-helix | helix | 192.168.10.11 | 10 | ✅ läuft |
| k3s-vega | vega | 192.168.10.12 | 10 | ✅ läuft |

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
| Nginx Proxy Manager | 192.168.10.75 | proxy.cantone.net | 80, 443, 81 (Admin) | Docker in LXC — MariaDB, dynamic DHCP |
| Step-CA | 192.168.10.56 | step-ca.cantone.net | 9000 | Docker in LXC — ACME aktiviert |
| Gotify | 192.168.10.52 | gotify.cantone.net | 443 (via NPM) | Docker in LXC |
| Homepage | 192.168.10.93 | homepage.cantone.net | 3000 | Docker in LXC — Docker-Socket gemountet, extern: dash.cantone.net |
| Semaphore | 192.168.10.57 | semaphore.cantone.net | 80 | Docker in LXC — MySQL 8.4.5 |
| Cloudflare DynDNS | 192.168.10.78 | cloudflare-ddns.cantone.net | — | Docker in LXC — wildcard *.cantone.net, PROXIED=true |
| Uptime Kuma | 192.168.10.91 | monitor.cantone.net | 3001 (via NPM, HTTP Only) | Docker in LXC |
| Nextcloud | 192.168.10.82 | nextcloud.cantone.net | 11000 (via NPM) | Nextcloud AIO — hinter NPM |

### VMs (nicht Terraform-verwaltet)

| Service | IP | DNS | Port | Notiz |
|---------|----|-----|------|-------|
| HomeAssistant | 192.168.10.61 | homeassistant.cantone.net | 8123 (via NPM, HTTP Only) | VM — nur Dev, keine Migration geplant |


### Media-Stack (Docker Compose auf Media-VM, läuft auf orion)

Config: `docs/legacy/docker-compose/media-stack.yml`

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

- Cluster läuft auf nova, helix, vega (je 1x 1TB **NVMe** als OSD) + orion (1x 1TB **SATA SSD**) — aktuell **4 OSDs**
- Nach Phase 1: orion wird entfernt → **3 OSDs** (nova, helix, vega)
- k3s VM-Disks und LXC-Storage liegen auf `ceph_data`

---

## Security-Status

| Thema | Status |
|-------|--------|
| SSH-Private-Key aus Git-History entfernen | ✅ Erledigt (git filter-repo) |
| Neues SSH-Keypair für Ansible generieren | ✅ Erledigt |
| `cipassword = "test123"` in `vm_k3s.tf` | ⚠️ Noch vorhanden — vor Produktion entfernen |
| `terraform.tfvars` (API-Credentials) | ✅ in `.gitignore` |
