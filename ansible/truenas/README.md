# TrueNAS Ansible Playbooks

Configures TrueNAS Scale fully via SSH + `midclt`.
Run from the local control node (e.g. WSL2).

## Bootstrapping (once, manually)

SSH is not active on a fresh TrueNAS instance. Enable it manually once:
> TrueNAS WebUI → **System → Services → SSH → Start + Enable autostart**
> TrueNAS WebUI → **Credentials → Users → root → SSH Public Keys → paste ansible.pub**

Ansible then takes over fully via `midclt`.

---

## Playbooks

### `configure.yml` — Main configuration

Configures ZFS pools, datasets, zvols, NFS, snapshots, scrubs, VMs, network, TLS, disk monitoring.

```bash
ansible-playbook ansible/truenas/configure.yml
```

**What it does (in order):**

1. **Disk resolution** — resolves configured serial numbers to current device names (`sda`/`sdb`/etc. are not stable across reboots)
2. **Disk wipe** — wipes disks (QUICK mode) before pool creation, only if the pool does not yet exist
3. **ZFS Pool `data`** — RAIDZ1 across 4 disks, created only if not already present
4. **ZFS Pool `archive`** — single-disk STRIPE (2TB SSD), created only if not already present
5. **Datasets** — creates configured datasets with properties (compression, recordsize, atime). Idempotent: existing datasets are updated.
6. **Zvols** — creates VM disks as thin-provisioned zvols (`sparse=true`, `volblocksize=16K`)
7. **Users** — creates `media` user (UID 1000, no login shell) for NFS ownership
8. **NFS Service** — starts NFS and enables autostart on boot
9. **NFS Shares** — creates/updates shares for configured paths (host-restricted)
10. **Snapshot Tasks** — daily snapshots with 2-week retention (only datasets with `snapshot: true`)
11. **Scrub Tasks** — monthly scrubs for both pools (1st of the month)
12. **S.M.A.R.T. Tests** — ⚠️ No midclt endpoint available. Configure manually: *Data Protection → S.M.A.R.T. Tests → Add*. Recommendation: SHORT weekly (Sunday 01:00), LONG monthly (1st 02:00)
13. **Step-CA root cert** — installs homelab CA in system trust store + TrueNAS CA store
14. **ACME certificate** — issues `truenas.cantone.net` cert via Step-CA, sets it as UI cert
15. **Disk monitor** — deploys `/root/disk-monitor.sh`, runs daily at 12:00 via cron (Gotify alert on CRC increase / ata errors)
16. **mediastack VM** — creates VM (8 vCPUs, 16GB RAM) with OS disk, downloads disk, Plex DB disk, NIC, VNC display
17. **Network** — configures bridge `br1`, static IP `192.168.10.25`, hostname, gateway, DNS. ⚠️ Goes last — commits briefly interrupt SSH. 120s rollback window with manual checkin.

The playbook is **idempotent**: running it multiple times is safe.

---

### `cloudsync.yml` — Offsite backup to Hetzner Storage Box

Sets up encrypted offsite backup via rclone crypt → Hetzner Storage Box (SFTP).

```bash
ansible-playbook ansible/truenas/cloudsync.yml
```

**Prerequisites:**
1. SSH public key `ssh/truenas-hetzner.pub` registered in Hetzner Storage Box console (SSH Keys section)
2. `vars/secrets.yml`: `hetzner_rclone_encryption_password` + `hetzner_rclone_encryption_salt` set
3. `ssh/truenas-hetzner` (private key) present locally (gitignored)

**What it does:**
1. **SSH_KEY_PAIR keychain credential** — registers `ssh/truenas-hetzner` in TrueNAS keychain (`hetzner-storagebox`). Normalises Windows `\r\n` line endings. Skipped if already exists.
2. **SFTP credential** — creates `Hetzner Storage Box` cloud sync credential using keychain ID. `pass` is always `""` (required by TrueNAS even when using key auth). Skipped if already exists.
3. **Cloud Sync tasks** — creates tasks from `cloudsync_tasks` in `vars/config.yml`. Each task:
   - Direction: PUSH, mode: SYNC
   - `snapshot: true` — TrueNAS takes a ZFS snapshot before syncing (consistent point-in-time copy)
   - Client-side rclone crypt encryption (`filename_encryption: true`)
   - Skipped if task with same description already exists

**Idempotency note:** If SFTP credential or keychain entry is deleted and recreated (new ID), also delete the Cloud Sync task manually and re-run — it stores the credential ID.

**Active tasks:**

| Dataset | Remote path | Schedule |
|---------|-------------|----------|
| `/mnt/data/mediastack/mediastack-config` | `/backups/mediastack-config` | Sunday 02:00 |

Longhorn backup task is defined in `config.yml` but commented out (Phase 3).

**Hetzner Storage Box snapshots:** Separately configured in Hetzner Robot UI. Runs every Monday, retains 5 snapshots (≈ 5 weeks).

---

### `audit.yml` — Drift detection

Checks whether more resources exist on TrueNAS than defined in `config.yml`. Read-only, no changes.

```bash
ansible-playbook ansible/truenas/audit.yml
```

Checks: pools, datasets/zvols, NFS shares. Reports unknown entries via `⚠️` debug message.

---

## Dataset Structure

Naming convention: `<hostname>-<usage>` — always lowercase

```
data/
├── mediastack/                          # Container dataset — no snapshot
│   ├── mediastack-config                # Dataset ~4GB — app configs (Plex, Radarr, Sonarr, etc.)
│   │   recordsize=16K                    # NFS share → 192.168.10.62 only (host-restricted)
│   ├── mediastack-data                  # Dataset ~4.5TB — movies, TV, music, audiobooks
│   │   recordsize=512K, atime=off       # NFS share → 192.168.10.62 only (host-restricted)
│   ├── mediastack-downloads             # Zvol 250GB — NZBGet download dir (thin, 16K)
│   └── mediastack-plexdb               # Zvol 80GB — Plex database + cache (thin, 16K)
└── vms/                                 # Container dataset — no snapshot
    └── mediastack-os                    # Zvol 90GB — Media VM OS disk (thin, 16K)

archive/                                 # Single-disk pool (Crucial BX500 2TB SSD)
                                         # Cold storage — no datasets configured yet
```

---

## Configuration

### `vars/config.yml`

Main configuration file (committed to Git):

```yaml
truenas_url: "https://192.168.10.25"
truenas_validate_certs: false

data_pool_serials:       # Stable disk identifiers (independent of sda/sdb ordering)
  - ZW611XR4             # 3TB Seagate
  - WD-WCC4N0PU0J03      # 3TB WD
  - ...
archive_pool_serial: 2327E6EB5451    # Crucial BX500 2TB SSD

datasets:
  - name: data/mediastack
    snapshot: false
  - name: data/mediastack/mediastack-data
    recordsize: 512K
    atime: "OFF"
  - name: data/mediastack/mediastack-config
    recordsize: 16K
    snapshot: true

zvols:
  - name: data/vms/mediastack-os
    volsize: 96636764160    # 90GB (must be integer bytes)
    volblocksize: "16K"
  - name: data/mediastack/mediastack-downloads
    volsize: "{{ mediastack_downloads_disk_size_gb * 1024 * 1024 * 1024 }}"
    volblocksize: "16K"

nfs_shares:
  - path: /mnt/data/mediastack/mediastack-config
    hosts: ["192.168.10.62"]
    mapall_user: media
    mapall_group: media
  - path: /mnt/data/mediastack/mediastack-data
    hosts: ["192.168.10.62"]
    mapall_user: media
    mapall_group: media

cloudsync_tasks:
  - description: "mediastack-config → Hetzner"
    path: "/mnt/data/mediastack/mediastack-config"
    folder: "/backups/mediastack-config"
    snapshot: true
    schedule:
      minute: "0"
      hour: "2"
      dom: "*"
      month: "*"
      dow: "0"    # Sunday
```

### `vars/secrets.yml`

Not in Git. Copy from template and fill in:

```bash
cp ansible/truenas/vars/secrets.example.yml ansible/truenas/vars/secrets.yml
```

```yaml
truenas_api_key: ""
truenas_vm_vnc_password: ""
disk_monitor_gotify_token: ""
hetzner_rclone_encryption_password: ""
hetzner_rclone_encryption_salt: ""
```

⚠️ Back up `hetzner_rclone_encryption_password` and `hetzner_rclone_encryption_salt` in Proton Pass.
Without these two values, data on Hetzner Storage Box is unrecoverable.

---

## Known Limitations

- **S.M.A.R.T. schedules** — no `midclt` endpoint available, configure manually in the WebUI
- **GPU passthrough** (P1-15) — Ryzen 7 3700X has no iGPU, TrueNAS refuses passthrough of the only GPU as long as no second display output is available. GTX 970 passthrough to media VM is pending.
- **`xattr` / `dnodesize`** — not supported by `pool.dataset.create`, cannot be set via Ansible

---

## File Structure

```
ansible/truenas/
├── configure.yml          # Main playbook — ZFS, NFS, VMs, network, TLS, monitoring
├── cloudsync.yml          # Offsite backup — Hetzner Storage Box via rclone crypt
├── audit.yml              # Drift detection (read-only)
├── README.md              # This file
├── files/
│   └── disk-monitor.sh    # Disk health monitor (deployed to /root/)
├── tasks/
│   └── wipe_disk.yml      # Wipe a single disk before pool creation
└── vars/
    ├── config.yml         # Configuration (in Git)
    ├── secrets.yml        # Secrets (gitignored)
    └── secrets.example.yml
```
