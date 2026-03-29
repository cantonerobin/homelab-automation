# Homelab — Original State (before migration)

> Snapshot of the infrastructure as it was in March 2026, before the TrueNAS migration began.
> This document serves as a historical reference — not the current state.
> See `current.md` for the current state and `roadmap.md` for the migration plan.

---

## Hardware

### PVE Node "orion" (→ became TrueNAS in Phase 1)
- CPU: Ryzen 7 3700X, 64GB RAM
- Disks: 2× 250GB SATA SSD, 1× 1TB SATA SSD, 1× 2TB SATA SSD
- Was a Ceph OSD member — evicted cleanly before shutdown
- Hosted the Media VM (Docker Compose stack)
- GPU: onboard Intel QuickSync → Plex HW-Transcoding via `/dev/dri`

### PVE Nodes nova / helix / vega (stayed as PVE)
- CPU: Intel i5-8500T, 16GB RAM
- Disks: 1× 250GB NVMe (OS), 1× 1TB NVMe (Ceph OSD)

### Synology NAS
- Disks: 1× 6TB HDD, 4× 3TB HDD
- All disks migrated to TrueNAS in Phase 1 — Synology decommissioned

---

## Network

| VLAN | Subnet | Name | Contents |
|------|--------|------|----------|
| 2 | 192.168.1.0/24 | Management | Firewall, Switches, APs, PVE nodes |
| 10 | 192.168.10.0/24 | Server | PVE nodes, k3s VMs, Synology |
| 20 | 192.168.20.0/24 | Client | Endpoints |
| 30 | 192.168.30.0/24 | DMZ | Externally exposed services |
| 40 | 192.168.40.0/24 | Untrust | WiFi, IoT |

| Host | IP | DNS |
|------|----|-----|
| helix | 192.168.10.20 | helix.cantone.net |
| vega | 192.168.10.21 | vega.cantone.net |
| nova | 192.168.10.22 | nova.cantone.net |
| orion | 192.168.10.25 | orion.cantone.net |
| nas01 (Synology) | 192.168.10.100 | — |

---

## Ceph

- 4 OSDs: nova + helix + vega (1TB NVMe each) + orion (1TB SATA SSD)
- All k3s VM disks and LXC storage on `ceph_data`
- Plan after Phase 1: remove orion OSD → 3 OSDs remaining
- Plan after Phase 2: remove Ceph entirely → 1TB NVMe per node as local-lvm

---

## Virtual Machines (Terraform-managed)

| VM | Node | IP | Status |
|----|------|----|--------|
| k3s-nova | nova | 192.168.10.10 | running |
| k3s-helix | helix | 192.168.10.11 | running |
| k3s-vega | vega | 192.168.10.12 | running |

- Template: `alma9-template-v1` (AlmaLinux 9 Cloud-Init)
- Storage: `ceph_data`

---

## Services

### LXC + Docker on PVE

| Service | IP | Notes |
|---------|----|-------|
| Nginx Proxy Manager | 192.168.10.75 | Reverse proxy for all services |
| Step-CA | 192.168.10.56 | Internal PKI, ACME enabled |
| Gotify | 192.168.10.52 | Push notifications |
| Homepage | 192.168.10.93 | Dashboard (Docker socket mounted) |
| Semaphore | 192.168.10.57 | Ansible UI — later dropped |
| Cloudflare DynDNS | 192.168.10.78 | Wildcard `*.cantone.net` |
| Uptime Kuma | 192.168.10.91 | Service monitoring |
| Nextcloud AIO | 192.168.10.82 | Behind NPM, data on Synology/Ceph |
| HomeAssistant | 192.168.10.61 | VM — dev only, no Zigbee passthrough yet |

### Media Stack (Docker Compose VM on orion)

Config preserved in `docs/legacy/docker-compose/media-stack.yml`.

| Service | Notes |
|---------|-------|
| Plex | HW-Transcoding via Intel QuickSync (`/dev/dri`) |
| NZBGet | Usenet downloader |
| Radarr | Movies |
| Sonarr | TV |
| Lidarr | Music |
| Prowlarr | Indexer management |
| Seerr | Request management (Overseerr fork) |
| Tautulli | Plex statistics |
| Wizarr | Plex invite management |
| Audiobookshelf | Audiobooks + podcasts |
| YTdl-Material | YouTube-DL web UI (yt-dlp + MongoDB) |

---

## What changed and why

| Topic | Before | After | Reason |
|-------|--------|-------|--------|
| Storage server | Synology NAS | TrueNAS Scale (orion) | More control, ZFS, VM hosting |
| Media VM GPU | Intel QuickSync (integrated) | GTX 970 (discrete) | No integrated GPU on TrueNAS hardware |
| Reverse proxy | Nginx Proxy Manager | ingress-nginx (k3s) | GitOps, IaC, no GUI clicking |
| Ansible UI | Semaphore | Dropped (CLI/CI directly) | Unnecessary complexity |
| LXC services | All on PVE Ceph | Migration → k3s (Phase 4) | Consolidation, GitOps |
| Plex location | Media VM on PVE/orion | Media VM on TrueNAS | GPU passthrough simpler under TrueNAS |
| Ceph | 4-node cluster | Removal (Phase 2) | 3 small nodes, NVMe better as local-lvm |
