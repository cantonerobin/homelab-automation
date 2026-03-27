# Homelab — Ist-Zustand

> Dieses File beschreibt den aktuellen Stand der Infrastruktur.
> Letzte Aktualisierung: 2026-03-27

---

## Hardware

### TrueNAS Scale "truenas" (192.168.10.25)
- CPU: Ryzen 7 3700X, 64GB RAM
- GPU (installiert): NVIDIA GTX 970 4GB (PCIe) — für Plex HW-Transcoding (P1-15)
- GPU (geplant): NVIDIA GTX 1060 6GB — für AI-VM (B-42, noch nicht eingebaut)

#### Disk-Inventar (Stand 2026-03-27, alle SMART-Werte erhoben)

| Device | Serial | Modell | Kapazität | Zweck | SMART-Status |
|--------|--------|--------|-----------|-------|-------------|
| sda | WD-WCC4N4CLA3YZ | WD Red WD30EFRX | 3TB HDD | data RAIDZ1 | ⚠️ UDMA_CRC=100 (Kabel) |
| sdb | WD-WCC4N3HVJ1FL | WD Red WD30EFRX | 3TB HDD | data RAIDZ1 | ⚠️ UDMA_CRC=21 (Kabel) |
| sdc | WD-WCC4N0PU0J03 | WD Red WD30EFRX | 3TB HDD | data RAIDZ1 | ✅ sauber |
| sde | ZW611XR4 | Seagate ST3000VN006 | 3TB HDD | data RAIDZ1 | ✅ sauber, 17.918h |
| sdf | 2327E6EB5451 | Crucial BX500 CT2000BX500SSD1 | 2TB SSD | archive Pool | ✅ sauber |
| sdg | S2R6NX0JC30444T | Samsung 850 EVO 250GB | 250GB SSD | OS Mirror (Disk 2) | ✅ sauber, 22.367h |
| sdd | 2L17292GA1TT | ADATA SU630 | 240GB SSD | OS Mirror (Disk 1) | ✅ 96% Life |
| sdh | WD-WX72D55LE2RP | WDC WD50NDZW-11BCSS0 | 5TB HDD | Externe HDD (Restore-Disk) — kein Pool, potentielles Backup-Ziel | ✅ sauber, 2.002h |

**Laufzeit RAIDZ1-Disks:** sda/sdb/sdc je ~60.000h (~6,8 Jahre). sde (Seagate) nur 17.918h — Ersatz aus der Synology.

#### SATA-Kabelprobleme: WD-WCC4N4CLA3YZ + WD-WCC4N3HVJ1FL (2026-03-27 behoben)

- **WD-WCC4N4CLA3YZ**: UDMA_CRC_Error_Count=100 (akkumuliert, steigt nicht mehr)
- **WD-WCC4N3HVJ1FL**: UDMA_CRC_Error_Count=21 (akkumuliert, steigt nicht mehr)
- **Ursache:** Wackelkontakt SATA-Kabel — Kabel neu eingesteckt 2026-03-27
- **Ergebnis:** Keine Hard Resets mehr in dmesg, CKSUM=0, CRC-Counter stabil
- **Monitoring:** `/root/disk-monitor.sh` läuft täglich 12:00 — Gotify-Alert bei CRC-Anstieg oder ata-Fehlern
- **Offen:** Falls neue Gotify-Alerts kommen → neue Ersatzkabel besorgen + anderen SATA-Port probieren

### PVE Nodes nova / helix / vega (bleiben PVE)
- CPU: Intel i5-8500T, 16GB RAM
- Disks: 1x 250GB NVMe (OS), 1x 1TB NVMe (Ceph OSD)
- Ceph-Cluster läuft auf diesen 3 Nodes
- ⚠️ **helix NVMe (Ceph OSD):** SMART Critical Warning `0x04` (Reliability) seit 2026-03-15 — siehe Ceph-Abschnitt

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
| truenas | 192.168.10.25 | truenas.cantone.net |

---

## TrueNAS Scale (truenas, 192.168.10.25)

> Konfiguriert via `ansible/truenas/configure.yml`

### ZFS Pools

| Pool | Disks | RAID | Zweck |
|------|-------|------|-------|
| `data` | 4x 3TB HDD | RAIDZ1 | Media, Downloads, Nextcloud, Backups, VM-Zvols |
| `archive` | 1x 6TB HDD | Stripe | Cold Storage |

### Datasets (`data` Pool)

Namenskonvention: `<hostname>-<verwendung>` — immer lowercase

| Dataset | Typ | Größe | Zweck |
|---------|-----|-------|-------|
| `data/mediastack` | Container | — | Organisationszweck, kein Snapshot |
| `data/mediastack/mediastack-data` | Dataset | — | Filme, Serien, Musik, Audiobooks (NFS) |
| `data/mediastack/mediastack-downloads` | Zvol | 250GB | NZBGet Downloads (direkt an VM) |
| `data/vms` | Container | — | Organisationszweck, kein Snapshot |
| `data/vms/mediastack-os` | Zvol | 40GB | Media VM OS-Disk |

Dataset-Optionen `mediastack-data`: `recordsize=512K`, `atime=off`, `compression=lz4`
Zvol-Optionen: `volblocksize=16K`, `sparse=true` (thin provisioned)

### NFS-Shares

| Pfad | Netz | Zweck |
|------|------|-------|
| `/mnt/data/mediastack/mediastack-data` | 192.168.10.0/24 | Filme, Serien, Musik, Audiobooks |

### TrueNAS VMs

| VM | vCPUs | RAM | Disk | GPU | Status |
|----|-------|-----|------|-----|--------|
| mediastack | 4 | 8GB | 40GB OS + 250GB Downloads | GTX 970 (P1-15 ⚠️) | ✅ OS installiert, vm_base ✅ |

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
| Gotify | 192.168.10.52 | notifications.cantone.net | 443 (via NPM) | Docker in LXC |
| Homepage | 192.168.10.93 | homepage.cantone.net | 3000 | Docker in LXC — extern: dash.cantone.net |
| Cloudflare DynDNS | 192.168.10.78 | cloudflare-ddns.cantone.net | — | Docker in LXC — wildcard *.cantone.net |
| Uptime Kuma | 192.168.10.91 | monitor.cantone.net | 3001 (via NPM) | Docker in LXC |
| Nextcloud | 192.168.10.82 | nextcloud.cantone.net | 11000 (via NPM) | Nextcloud AIO |

### VMs (nicht Terraform-verwaltet)

| Service | IP | DNS | Port | Notiz |
|---------|----|-----|------|-------|
| HomeAssistant | 192.168.10.61 | homeassistant.cantone.net | 8123 (via NPM) | Dev-VM — Prod mit USB-Passthrough ausstehend |

### Media-Stack

> ⚠️ Migration läuft — Services laufen noch auf altem PVE-LXC. TrueNAS VM (192.168.10.62) ist bereit, Services noch nicht migriert (P1-16/P1-17).
> ✅ Daten-Restore abgeschlossen (P1-11): ~4.5TB von ext. HDD → `/mnt/data/mediastack/mediastack-data/`

Config (Legacy): `docs/legacy/docker-compose/media-stack.yml`

| Service | Port | Notiz |
|---------|------|-------|
| Plex | 32400 | HW-Transcoding ausstehend (P1-15 ⚠️ GPU-Passthrough blockiert) |
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

- Cluster läuft auf nova, helix, vega (je 1x 1TB **NVMe** als OSD) — **3 OSDs** (orion/truenas bereits entfernt — war ehem. PVE-Node)
- k3s VM-Disks und LXC-Storage liegen auf `ceph_data`
- ⚠️ Ceph wird in Phase 2 entfernt → 1TB NVMe pro Node wird local-lvm

### ⚠️ Hardware-Warnung: helix NVMe (Ceph OSD)

- **Disk:** Kingston SNV3S1000G (S/N: `50026B7383A61853`) — 1TB NVMe auf **helix**, `/dev/nvme0`
- **Problem:** SMART Critical Warning `0x04` (Reliability degraded) — erstmals gemeldet 2026-03-15
- **Rolle:** Ceph OSD — Ausfall würde Ceph-Cluster beeinträchtigen (nur 2 OSDs übrig bei RAIDZ)
- **Aktion:** Disk ersetzen sobald Ceph in Phase 2 abgebaut wird. Bis dahin Ceph-Status im Auge behalten (`ceph -s`). Kein dringender Handlungsbedarf solange Ceph redundant bleibt.

---

## Security-Status

| Thema | Status |
|-------|--------|
| SSH-Private-Key aus Git-History entfernen | ✅ Erledigt (git filter-repo) |
| Neues SSH-Keypair für Ansible generieren | ✅ Erledigt |
| `cipassword` in Cloud-Init Template | ✅ Entfernt — nur SSH-Key Auth |
| `terraform.tfvars` (API-Credentials) | ✅ in `.gitignore` |
