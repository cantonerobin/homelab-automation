# Homelab — Target Architecture

> This file describes the desired target state of the homelab.
> Changes here mean: roadmap (`roadmap.md`) must be updated accordingly.
> Last updated: 2026-03-28

---

## Overview

```
┌─────────────────────────────────────────────────────┐
│  PVE Cluster (nova, helix, vega)                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │ k3s-nova │  │k3s-helix │  │ k3s-vega │  (VMs)  │
│  └──────────┘  └──────────┘  └──────────┘          │
│  Storage: local-lvm (1TB NVMe/Node, after Phase 2)  │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  TrueNAS Scale (truenas)                            │
│  ZFS data (4x3TB RAIDZ1) + archive (2TB SSD)       │
│  ┌──────────────────────┐                           │
│  │  Media VM            │                           │
│  │  (Plex + NZBGet)     │                           │
│  │  GPU: GTX 970        │                           │
│  └──────────────────────┘                           │
│  ┌──────────────────────────┐                       │
│  │  AI VM                   │                       │
│  │  (Ollama / Inference)    │                       │
│  │  GPU: GTX 1060 6GB       │                       │
│  └──────────────────────────┘                       │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  DNS Infrastructure (Raspberry Pi 4 × 2)            │
│  ┌──────────────────┐  ┌──────────────────┐        │
│  │  Pi 1 — Primary  │  │  Pi 2 — Secondary│        │
│  │  AdGuard Home    │◄─►  AdGuard Home    │        │
│  └──────────────────┘  └──────────────────┘        │
│  Deliberately outside k3s — critical infrastructure │
└─────────────────────────────────────────────────────┘
```

---

## Hardware (Target State)

### TrueNAS Node "truenas" (former PVE node "orion")
- CPU: Ryzen 7 3700X, 64GB RAM
- OS: TrueNAS Scale (on 2x 250GB SATA SSD mirror)
- L2ARC: 1x 1TB SATA SSD
- VM storage: 1x 2TB SATA SSD
- GPU 1: NVIDIA GTX 970 4GB → GPU passthrough to media VM (Plex HW-transcoding)
- GPU 2: NVIDIA GTX 1060 6GB → GPU passthrough to AI VM (Ollama, Inference)

### PVE Nodes nova / helix / vega
- Freshly installed (Phase 2, rolling)
- Ansible-configured (SSH)
- Storage: 1x 250GB NVMe (OS), 1x 1TB NVMe (local-lvm datastore — replaces Ceph OSD)

### Raspberry Pi 4 (2x) — DNS Infrastructure

| Pi | Role | Rationale |
|----|------|-----------|
| Pi 1 | AdGuard Home Primary | Critical DNS infrastructure outside k3s |
| Pi 2 | AdGuard Home Secondary | Redundancy — automatic failover |

- AdGuard Home Sync: filter lists + settings automatically synchronised
- Router/DHCP: both IPs configured as DNS servers → automatic failover
- Deliberately outside k3s: DNS remains available across the entire network during k3s restart/failure

---

## Network

VLAN schema remains unchanged. Changes compared to current state:

| VLAN | Subnet | Name | Contents |
|------|--------|------|----------|
| 1 | 192.168.1.0/24 | Management | Firewall, switches, APs, PVE nodes, TrueNAS |
| 10 | 192.168.10.0/24 | Server | k3s VMs + services |
| 20 | 192.168.20.0/24 | Client | Endpoints |
| 30 | 192.168.30.0/24 | DMZ | Externally exposed services |
| 40 | 192.168.40.0/24 | Untrust | WLAN, IoT |

- **truenas:** withdraws from VLAN 10 → management only (VLAN 1)
- **Synology:** removed (disks → TrueNAS)
- **k3s VMs:** remain static in VLAN 10 (192.168.10.10–.12)
- **PVE nodes nova/helix/vega:** IPs unchanged
- **DNS:** both Raspberry Pi 4 as primary DNS servers in the network (AdGuard Home)

---

## ZFS Pool Design (TrueNAS)

| Pool | Disks | RAID | Usable | Purpose |
|------|-------|------|--------|---------|
| `data` | 4x 3TB (ex-Synology) | RAIDZ1 | ~9TB | Media, Nextcloud, backups |
| `archive` | 1x 2TB SSD (Crucial BX500, ex-Synology) | Standalone | ~2TB | Cold storage |
| OS Boot | 2x 250GB SATA SSD | Mirror | — | TrueNAS OS |
| L2ARC | 1x 1TB SATA SSD | — | — | Read cache |
| VM disks | 1x 2TB SATA SSD | — | — | Media VM + AI VM |

> Configuration via Ansible against TrueNAS REST API (`/api/v2.0`) — pools, datasets, NFS shares, snapshot tasks.

### Datasets (on `data` pool)

| Dataset | Path | Recordsize | Compression | Used by |
|---------|------|------------|-------------|---------|
| `media` | `/mnt/data/media` | 1M | LZ4 | Plex VM (direct), k3s (NFS) |
| `downloads` | `/mnt/data/downloads` | 128k | LZ4 | Media VM (NFS) |
| `backups` | `/mnt/data/backups` | 128k | ZSTD | Config backups, Longhorn |
| `backups/longhorn` | `/mnt/data/backups/longhorn` | 128k | ZSTD | Longhorn backup target (k3s) |
| `nextcloud` | `/mnt/data/nextcloud` | 16k | LZ4 | k3s (NFS) |

---

## VMs on TrueNAS (KVM)

| VM | CPU | RAM | Disk | GPU | Purpose |
|----|-----|-----|------|-----|---------|
| mediastack | 4 cores | 16GB | 50GB OS + 50GB config | GTX 970 (passthrough) | Plex + NZBGet |
| ai | 4 cores | 16GB | TBD | GTX 1060 6GB (passthrough) | Ollama / AI inference |

---

## k3s Cluster

- 3 nodes: **all server nodes** (HA, embedded etcd) — no dedicated agent
- IPs: 192.168.10.10 / .11 / .12, VLAN 10, gateway 192.168.10.1
- Terraform-provisioned (AlmaLinux 9 Cloud-Init)
- Ansible-configured (k3s installation + updates)
- Init: k3s-nova with `--cluster-init`, helix + vega join via `--server`

### VM Disk Layout per k3s Node

| Disk | Size | Purpose |
|------|------|---------|
| Root disk (virtio) | 40GB | OS, k3s binaries, container images |
| Longhorn disk (virtio) | 100GB | `/var/lib/longhorn` — dedicated for Longhorn storage |

### Kubernetes Platform

| Component | Tool | Purpose |
|-----------|------|---------|
| GitOps | ArgoCD (App-of-Apps) | Sync from `k3s-manifests` repo |
| Ingress | ingress-nginx | HTTP/HTTPS routing |
| Certificates | cert-manager + Step-CA | Internal TLS certs |
| Storage (shared) | NFS Subdir Provisioner | RWX PVCs on TrueNAS NFS (media, Nextcloud) |
| Storage (stateful) | Longhorn | RWO PVCs for DBs + stateful apps, replicated across 3 nodes |
| Secrets | Sealed Secrets | kubeseal-encrypted, committed to Git — back up cluster key! |
| SSO | Authentik | Single sign-on for app services |
| Monitoring | ❓ Evaluate after Phase 3 | Candidate: Grafana + Prometheus |

---

## Disaster Recovery

| Layer | What | Where | Offsite |
|-------|------|-------|---------|
| Data | TrueNAS `data` pool | Hetzner Storage Box via rclone (cloud sync) | ✅ |
| Databases | Longhorn backups | TrueNAS NFS (`backups/longhorn`) → carried along via rclone | ✅ |
| Configuration | Git | GitLab.com push mirror | ✅ |

**In case of total hardware loss:** Infrastructure can be rebuilt via Git + Terraform + Ansible, data restored from Hetzner Storage Box.

---

## Services — Target State

### Dedicated Hardware (outside k3s)

| Service | Hardware | Rationale |
|---------|----------|-----------|
| AdGuard Home Primary | Raspberry Pi 4 | DNS = critical infrastructure, k3s-independent |
| AdGuard Home Secondary | Raspberry Pi 4 | Redundancy / failover |

### PVE (dedicated VMs, not k3s)

| Service | VM | Rationale |
|---------|----|-----------|
| HomeAssistant | Dedicated PVE VM | USB passthrough (Zigbee stick) not possible in k3s |
| Plex | TrueNAS KVM VM | HW-transcoding via GTX 970 GPU passthrough |
| NZBGet | TrueNAS KVM VM | Performance (no NFS overhead) |
| AI / Ollama | TrueNAS KVM VM | GTX 1060 6GB GPU passthrough, local inference |

> **Media stack migration strategy:** All services continue running on TrueNAS media VM after Phase 1. After Phase 3 (k3s stable), services are migrated individually to k3s — minimal downtime per service, as external users are affected.

### k3s (via ArgoCD from `k3s-manifests`)

| Service | Priority | State | Authentik |
|---------|----------|-------|-----------|
| Cloudflare DynDNS | High | None | ✗ |
| Homepage | High | None | ✓ |
| Uptime Kuma | High | Small | ✓ |
| Gotify | Medium | Small | ✗ (internal) |
| Step-CA | Medium | Critical | ✗ (infra) |
| Authentik | High | DB (Longhorn) | — (is the SSO provider) |
| Nextcloud | Medium | NFS + DB (Longhorn) | ✓ |
| Firefly III | Medium | DB (Longhorn) | ✓ |
| GitLab | Low | DB (Longhorn) | ✓ |
| Audiobookshelf | Medium | NFS | ✓ |
| Radarr | Medium | NFS | ✓ |
| Sonarr | Medium | NFS | ✓ |
| Lidarr | Medium | NFS | ✓ |
| Prowlarr | Medium | Small | ✓ |
| Seerr | Medium | Small | ✓ |
| Tautulli | Medium | Small | ✓ |
| Wizarr | Low | Small | ✗ (Plex-internal) |
| YTdl-Material | Low | MongoDB (Longhorn) | ✓ |

---

## Git Repositories

### `homelab-automation` (this repo)
```
terraform/proxmox/    # VM provisioning
ansible/proxmox/      # PVE node configuration
ansible/truenas/      # ZFS pools, NFS shares, datasets
ansible/k3s/          # k3s bootstrap + node config
docs/
```

### `k3s-manifests` (to be created)
```
bootstrap/root-app.yaml     # apply manually once
apps/core/                  # cert-manager, ingress-nginx, sealed-secrets, longhorn, nfs-provisioner
apps/auth/                  # Authentik
apps/media/                 # Radarr, Sonarr, Lidarr, Prowlarr, Seerr, Tautulli, Wizarr, Audiobookshelf, YTdl-Material
apps/services/              # Homepage, Gotify, DynDNS, Uptime Kuma, Nextcloud, Firefly III, GitLab
apps/monitoring/            # Grafana + Prometheus (evaluate after Phase 3)
apps/argocd/                # ArgoCD self-managed
docs/
```

---

## Architecture Decisions

| Topic | Decision | Rationale |
|-------|----------|-----------|
| GitOps | ArgoCD (App-of-Apps pattern) | Standard, well documented |
| HomeAssistant | Dedicated PVE VM | USB passthrough (Zigbee stick) not possible in k3s |
| GitLab | GitHub transition → self-hosted after Phase 3, push mirror to GitLab.com | Offsite backup, later source of truth |
| Secret Management | Sealed Secrets | kubeseal local, SealedSecret committed to Git. Cluster key must be backed up (TrueNAS) |
| Monitoring | ❓ Open — evaluate after Phase 3 | Elastic Stack dropped (too resource-intensive). Candidate: Grafana + Prometheus |
| NZBGet | TrueNAS VM permanently | Performance — no NFS overhead |
| k3s PVC Storage | Hybrid: Longhorn (RWO/DBs) + NFS (RWX/Media/Nextcloud) | Longhorn for replication + backup, NFS for shared large files |
| k3s Longhorn disk | 2 virtio disks per VM: root 40GB + Longhorn 100GB | IO separation OS/replication, independently resizable |
| PVE Storage | local-lvm (after Phase 2, Ceph removed) | Ceph too complex for 3-node setup without dedicated Ceph nodes |
| PVE Reinstall | netboot.xyz | PoC POC-1 before Phase 2 |
| k3s static IPs | Cloud-Init in Terraform | More flexible than Unifi DHCP reservation |
| k3s HA | 3 server nodes (embedded etcd) | No SPOF on control plane — all nodes equal |
| Semaphore | Dropped | Ansible directly via CLI or CI |
| Authentik | Deploy early, all app services | NOT for infra tools (Proxmox, TrueNAS, ArgoCD, Longhorn) — VPN-only access |
| Nextcloud | Two-stage: AIO on TrueNAS VM → PoC → migrate to k3s | Gentle migration, data stays on existing NFS dataset |
| NPM → ingress-nginx | ❓ Cutover plan still to be defined | Coordinated switch of all DNS/Cloudflare entries required |
| Network source of truth | Pure IaC (variables.tf, hosts.yml) | Netbox optional as visualisation when k3s is stable |
| DNS infrastructure | AdGuard Home on 2x Raspberry Pi 4 (Primary + Secondary) | DNS = critical infrastructure, must not depend on k3s availability. hostNetwork/MetalLB in k3s solvable but suboptimal. Sync via AdGuard Home Sync |
| GPU allocation (truenas) | GTX 970 → Plex (media VM), GTX 1060 6GB → AI VM | Two dedicated GPUs, one VM each — no sharing needed |
| AI / Inference | Dedicated TrueNAS VM with GTX 1060 6GB | Ollama etc. — 6GB VRAM: 13B models with quantisation possible |
