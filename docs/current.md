# Homelab — Current State

> This file describes the current state of the infrastructure.
> Last updated: 2026-04-08

---

## Hardware

### TrueNAS Scale "truenas" (192.168.10.25)
- CPU: Ryzen 7 3700X, 64GB RAM
- GPU (installed): NVIDIA GTX 970 4GB (PCIe) — for Plex HW-transcoding (P1-15)
- GPU (planned): NVIDIA GTX 1060 6GB — for AI VM (B-42, not yet installed)

#### Disk Inventory (as of 2026-03-27, all SMART values collected)

| Device | Serial | Model | Capacity | Purpose | SMART Status |
|--------|--------|-------|----------|---------|-------------|
| sda | WD-WCC4N4CLA3YZ | WD Red WD30EFRX | 3TB HDD | data RAIDZ1 | ⚠️ UDMA_CRC=100 (cable) |
| sdb | WD-WCC4N3HVJ1FL | WD Red WD30EFRX | 3TB HDD | data RAIDZ1 | ⚠️ UDMA_CRC=21 (cable) |
| sdc | WD-WCC4N0PU0J03 | WD Red WD30EFRX | 3TB HDD | data RAIDZ1 | ✅ clean |
| sde | ZW611XR4 | Seagate ST3000VN006 | 3TB HDD | data RAIDZ1 | ✅ clean, 17,918h |
| sdf | 2327E6EB5451 | Crucial BX500 CT2000BX500SSD1 | 2TB SSD | archive pool | ✅ clean |
| sdg | S2R6NX0JC30444T | Samsung 850 EVO 250GB | 250GB SSD | OS mirror (disk 2) | ✅ clean, 22,367h |
| sdd | 2L17292GA1TT | ADATA SU630 | 240GB SSD | OS mirror (disk 1) | ✅ 96% life |
| sdh | WD-WX72D55LE2RP | WDC WD50NDZW-11BCSS0 | 5TB HDD | External HDD (restore disk) — no pool, potential backup target | ✅ clean, 2,002h |

**Runtime RAIDZ1 disks:** sda/sdb/sdc each ~60,000h (~6.8 years). sde (Seagate) only 17,918h — replacement from Synology.

#### SATA Cable Issues: WD-WCC4N4CLA3YZ + WD-WCC4N3HVJ1FL (resolved 2026-03-27)

- **WD-WCC4N4CLA3YZ**: UDMA_CRC_Error_Count=100 (accumulated, no longer increasing)
- **WD-WCC4N3HVJ1FL**: UDMA_CRC_Error_Count=21 (accumulated, no longer increasing)
- **Cause:** Loose SATA cable connection — cable reseated 2026-03-27
- **Result:** No more hard resets in dmesg, CKSUM=0, CRC counter stable
- **Monitoring:** `/root/disk-monitor.sh` runs daily at 12:00 — Gotify alert on CRC increase or ata errors
- **Open:** If new Gotify alerts appear → get replacement cables + try different SATA port

### PVE Nodes nova / helix / vega (remain PVE)
- CPU: Intel i5-8500T, 16GB RAM
- Disks: 1x 250GB NVMe (OS), 1x 1TB NVMe (Ceph OSD)
- Ceph cluster runs on these 3 nodes
- ⚠️ **helix NVMe (Ceph OSD):** SMART Critical Warning `0x04` (Reliability) since 2026-03-15 — see Ceph section

### Synology NAS
- ⚠️ Disks removed → installed in TrueNAS
- Device empty / no longer in operation

### Raspberry Pi (2x Pi 4)

| Pi | Hostname | IP | Role | Status |
|----|----------|----|------|--------|
| Pi 1 | pi01 | 192.168.1.2 | AdGuard Home Primary DNS | ❌ not yet configured |
| Pi 2 | pi02 | 192.168.1.3 | AdGuard Home Secondary DNS | ❌ not yet configured |

- Deliberately outside k3s — DNS is critical infrastructure
- AdGuard Home Sync between both instances planned
- Both IPs configured as DNS servers in router/DHCP
- Connected via small Unifi switch, ports 4+5, Native VLAN Management (VLAN 1) ✅

---

## Network

### VLAN Schema

| VLAN | Subnet | Name | Contents |
|------|--------|------|----------|
| 1 | 192.168.1.0/24 | Management | Firewall, switches, APs, PVE nodes |
| 10 | 192.168.10.0/24 | Server | PVE nodes, k3s VMs + services, TrueNAS |
| 20 | 192.168.20.0/24 | Client | Endpoints |
| 30 | 192.168.30.0/24 | DMZ | Externally exposed services |
| 40 | 192.168.40.0/24 | Untrust | WLAN, IoT |

- Trunk ports on PVE nodes and Unifi configured ✅ — all VLANs allowed
- DHCP Option 66/67 for netboot.xyz configured ✅

### Switch: Small Unifi Switch

| Port | Device | Native VLAN |
|------|--------|-------------|
| 1 | Nvidia Shield | Untrust / IOT (VLAN 40) |
| 2 | Uplink → Router | Default / Management (VLAN 1) |
| 4 | Pi 1 (pi01) | Default / Management (VLAN 1) |
| 5 | Pi 2 (pi02) | Default / Management (VLAN 1) |

### Node IPs (static, VLAN 10)

| Host | IP | DNS |
|------|----|-----|
| helix | 192.168.10.20 | helix.cantone.net |
| vega | 192.168.10.21 | vega.cantone.net |
| nova | 192.168.10.22 | nova.cantone.net |
| truenas | 192.168.10.25 | truenas.cantone.net |

---

## TrueNAS Scale (truenas, 192.168.10.25)

> Configured via `ansible/truenas/configure.yml`

### ZFS Pools

| Pool | Disks | RAID | Purpose |
|------|-------|------|---------|
| `data` | 4x 3TB HDD | RAIDZ1 | Media, downloads, Nextcloud, backups, VM zvols |
| `archive` | 1x 2TB SSD (Crucial BX500, S/N: 2327E6EB5451) | Stripe | Cold storage |

### Datasets (`data` pool)

Naming convention: `<hostname>-<usage>` — always lowercase

| Dataset | Type | Size | Purpose |
|---------|------|------|---------|
| `data/mediastack` | Container | — | Organisational, no snapshot |
| `data/mediastack/mediastack-config` | Dataset | ~4GB | App configs: Plex, Radarr, Sonarr, etc. — backed up to Hetzner |
| `data/mediastack/mediastack-data` | Dataset | ~4.5TB | Movies, TV shows, music, audiobooks (NFS) |
| `data/mediastack/mediastack-downloads` | Zvol | 250GB | NZBGet downloads (directly attached to VM) |
| `data/mediastack/mediastack-plexdb` | Zvol | 80GB | Plex database/cache (directly attached to VM) |
| `data/nextcloud` | Container | — | Organisational, no snapshot |
| `data/nextcloud/nextcloud-data` | Dataset | — | Nextcloud user data (NFS to 192.168.30.82) — `recordsize=16K`, `atime=off` |
| `data/nextcloud/nextcloud-config` | Dataset | — | AIO mastercontainer config + NC app files (NFS to 192.168.30.82) — `recordsize=4K` |
| `data/nextcloud/nextcloud-db` | Dataset | — | MariaDB data + DB dumps (NFS to 192.168.30.82) — `recordsize=16K`, `atime=off` |
| `data/vms` | Container | — | Organisational, no snapshot |
| `data/vms/mediastack-os` | Zvol | 90GB | Media VM OS disk |

Dataset options `mediastack-data`: `recordsize=512K`, `atime=off`, `compression=lz4`
Zvol options: `volblocksize=16K`, `sparse=true` (thin provisioned)

### NFS Shares

| Path | Allowed Hosts | Purpose |
|------|---------------|---------|
| `/mnt/data/mediastack/mediastack-config` | 192.168.10.62, 192.168.30.62 | App configs: Plex, Radarr, Sonarr, etc. |
| `/mnt/data/mediastack/mediastack-data` | 192.168.10.62, 192.168.30.62 | Movies, TV shows, music, audiobooks |
| `/mnt/data/nextcloud/nextcloud-data` | 192.168.30.82 | Nextcloud user data |
| `/mnt/data/nextcloud/nextcloud-config` | 192.168.30.82 | AIO mastercontainer config + NC app files |
| `/mnt/data/nextcloud/nextcloud-db` | 192.168.30.82 | MariaDB data + DB dumps |

### TrueNAS VMs

| VM | vCPUs | RAM | Disk | GPU | Status |
|----|-------|-----|------|-----|--------|
| mediastack | 8 | 16GB | 90GB OS + 250GB downloads + 80GB Plex DB | GTX 970 (passthrough deferred) | ✅ running — DMZ VLAN 30 (192.168.30.62, br30) |

---

## Virtual Machines (Terraform-managed, PVE)

| VM | Node | IP | VLAN | Status |
|----|------|----|------|--------|
| k3s-nova | nova | 192.168.10.10 | 10 | ✅ running |
| k3s-helix | helix | 192.168.10.11 | 10 | ✅ running |
| k3s-vega | vega | 192.168.10.12 | 10 | ✅ running |
| netboot | vega | 192.168.10.156 | 10 | ✅ running — hosts netboot.xyz |
| dev | nova | 192.168.10.61 | 10 | ✅ running — HomeAssistant dev |

- Template: `alma9-template-v1` (AlmaLinux 9 Cloud-Init, ID 9000)
- Terraform provider: `telmate/proxmox 3.0.2-rc07`
- Storage: `ceph_data`

---

## Services (LXC-based)

> Standard pattern: LXC + Docker inside. Exception: large services run in a VM.
> LXC node assignment irrelevant — storage on Ceph, LXCs migratable at any time.
> DNS schema: internal = `<service>.cantone.net`, external (Cloudflare) = own name → redirect to internal.

### LXC Services (on PVE)

| Service | IP | Internal DNS | Port | Note |
|---------|----|-------------|------|------|
| Nginx Proxy Manager | 192.168.30.75 | proxy.cantone.net | 80, 443, 81 (Admin) | Docker in LXC — MariaDB — DMZ VLAN 30 |
| Step-CA | 192.168.10.56 | step-ca.cantone.net | 9000 | Docker in LXC — ACME enabled |
| Gotify | 192.168.10.52 | notifications.cantone.net | 443 (via NPM) | Docker in LXC |
| Homepage | 192.168.10.93 | homepage.cantone.net | 3000 | Docker in LXC — external: dash.cantone.net |
| Cloudflare DynDNS | 192.168.10.78 | cloudflare-ddns.cantone.net | — | Docker in LXC — wildcard *.cantone.net |
| Uptime Kuma | 192.168.10.91 | monitor.cantone.net | 3001 (via NPM) | Docker in LXC |
| Nextcloud | 192.168.30.82 | nextcloud.cantone.net | 11000 (via NPM) | Nextcloud AIO — DMZ VLAN 30 — data on TrueNAS NFS (data/nextcloud/nextcloud-data) |

### VMs (not Terraform-managed)

| Service | IP | DNS | Port | Note |
|---------|----|-----|------|------|
| HomeAssistant | 192.168.10.61 | homeassistant.cantone.net | 8123 (via NPM) | Dev VM — prod with USB passthrough pending |

### Media Stack

> ✅ Migration complete — mediastack VM running on TrueNAS, DMZ VLAN 30 (192.168.30.62). Media data + config migrated and tested.
> ✅ Data restore complete (P1-11): ~4.5TB from external HDD → `/mnt/data/mediastack/mediastack-data/`
> ✅ DMZ migration complete (2026-04-05): VM moved from Server VLAN 10 → DMZ VLAN 30, NFS shares accessible from both VLANs.

Config (legacy): `docs/legacy/docker-compose/media-stack.yml`

| Service | Port | Note |
|---------|------|------|
| Plex | 32400 | HW-transcoding pending (P1-15 ⚠️ GPU passthrough blocked) |
| NZBGet | 6789 | Usenet downloader |
| Radarr | 7878 | Movies |
| Sonarr | 8989 | TV shows |
| Lidarr | 8686 | Music |
| Prowlarr | 9696 | Indexer management |
| Seerr | 5055 | Overseerr fork (request management) |
| Tautulli | 8181 | Plex statistics |
| Wizarr | 5690 | Plex invitation management |
| Audiobookshelf | 13378 | Audiobooks + podcasts |
| YTdl-Material | 8998 | YouTube-DL web UI (yt-dlp, with MongoDB) |

---

## Offsite Backup (Hetzner Storage Box)

| Item | Value |
|------|-------|
| Provider | Hetzner Storage Box |
| Host | u568390.your-storagebox.de |
| User | u568390 |
| SSH Port | 23 |
| SSH Key | `ssh/truenas-hetzner` (gitignored) |
| Encryption | rclone crypt (client-side) — passwords in Proton Pass + `secrets.yml` |
| Configured via | `ansible/truenas/cloudsync.yml` |

### Active Cloud Sync Tasks (TrueNAS)

TrueNAS takes a ZFS snapshot of the dataset before each sync (`snapshot: true`) to ensure a consistent point-in-time backup.

| Dataset | Remote Path | Schedule | Snapshot Mode | Status |
|---------|-------------|----------|---------------|--------|
| `/mnt/data/mediastack/mediastack-config` | `/backups/mediastack-config` | Sunday 02:00 | ✅ | ✅ Active |
| `/mnt/data/backups/longhorn` | `/backups/longhorn` | Sunday 02:30 | ✅ | ❌ Phase 3 |

#### Known Issue: Hetzner SFTP cannot mkdir top-level directories (resolved 2026-04-06)

- **Symptom:** `Put mkParentDir failed: mkdir "/backups" failed: sftp: "Failure" (SSH_FX_FAILURE)` — 22937 errors, sync fails completely
- **Cause:** Hetzner Storage Box SFTP returns `SSH_FX_FAILURE` when rclone tries to create root-level directories. rclone normally creates missing dirs itself, but Hetzner's SFTP implementation does not support this.
- **Fix:** Pre-create all required remote directories via SSH before the first sync. Done once manually (`mkdir -p backups`), and now automated in `tasks/cloudsync_tasks.yml` — the playbook SSHes to the Storage Box and runs `mkdir -p` for each configured folder path on every run (idempotent).
- **Note:** If a new backup folder is added to `config.yml`, the Ansible playbook handles creation automatically on next run.

### Hetzner Storage Box Snapshots

Hetzner-level snapshots run independently of the TrueNAS sync, providing an additional recovery layer.

| Setting | Value |
|---------|-------|
| Schedule | Every Monday |
| Retention | 5 snapshots (≈ 5 weeks) |
| Configured via | Hetzner Robot / Storage Box UI |

**Recovery layers (mediastack-config):**
1. TrueNAS ZFS snapshots — local, daily, 2 weeks retention
2. Hetzner Storage Box snapshots — 5 weekly copies (interim until Restic, B-47)
3. rclone crypt sync — current state always available as individual files on Hetzner

---

## Ceph

- Cluster runs on nova, helix, vega (1x 1TB **NVMe** each as OSD) — **3 OSDs** (truenas already evacuated + removed from cluster ✅)
- k3s VM disks and LXC storage reside on `ceph_data`
- ⚠️ Ceph will be removed in Phase 2 → 1TB NVMe per node becomes local-lvm

### ⚠️ Hardware Warning: helix NVMe (Ceph OSD)

- **Disk:** Kingston SNV3S1000G (S/N: `50026B7383A61853`) — 1TB NVMe on **helix**, `/dev/nvme0`
- **Issue:** SMART Critical Warning `0x04` (Reliability degraded) — first reported 2026-03-15
- **Role:** Ceph OSD — failure would impact Ceph cluster (only 2 OSDs remaining with RAIDZ)
- **Action:** Replace disk once Ceph is decommissioned in Phase 2. Until then monitor Ceph status (`ceph -s`). No urgent action required as long as Ceph remains redundant.

---

## Security Status

| Topic | Status |
|-------|--------|
| Remove SSH private key from Git history | ✅ Done (git filter-repo) |
| Generate new SSH keypair for Ansible | ✅ Done — `ssh/ansible` (gitignored) |
| Generate SSH keypair for Hetzner sync | ✅ Done — `ssh/truenas-hetzner` (gitignored) |
| `cipassword` in Cloud-Init template | ✅ Removed — SSH key auth only |
| `terraform.tfvars` (API credentials) | ✅ in `.gitignore` |
| rclone crypt passwords | ✅ in `secrets.yml` (gitignored) — back up in Proton Pass |
