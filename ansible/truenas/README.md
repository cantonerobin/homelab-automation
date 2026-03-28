# TrueNAS Ansible Playbook

Configures TrueNAS Scale fully via SSH + `midclt`.
Run from the local control node (e.g. WSL2).

## Bootstrapping (once, manually)

SSH is not active on a fresh TrueNAS instance. Enable it manually once:
> TrueNAS WebUI → **System → Services → SSH → Start + Enable autostart**
> TrueNAS WebUI → **Credentials → Users → root → SSH Public Keys → paste ansible.pub**

Ansible then takes over fully via `midclt`.

---

## What the playbook does

1. **Disk resolution** — resolves configured serial numbers to current device names (sda/sdb/etc. are not stable across reboots)
2. **Disk wipe** — wipes disks (QUICK mode) before creating pools, only if the pool does not yet exist
3. **ZFS Pool `data`** — RAIDZ1 across 4 disks, created only if not already present
4. **ZFS Pool `archive`** — single-disk STRIPE, created only if not already present
5. **Datasets** — creates configured datasets with properties (compression, recordsize, atime). Idempotent: existing datasets are updated.
6. **Zvols** — creates VM disks as thin-provisioned zvols (`sparse=true`, `volblocksize=16K`)
7. **NFS Service** — starts NFS and enables autostart on boot
8. **NFS Shares** — creates shares for configured paths, skips already existing ones
9. **Snapshot Tasks** — daily snapshots with 2-week retention (only datasets with `snapshot: true`)
10. **Scrub Tasks** — monthly scrubs for both pools (1st of the month)
11. **S.M.A.R.T. Tests** — ⚠️ No midclt endpoint available. Configure manually: *Data Protection → S.M.A.R.T. Tests → Add*. Recommendation: SHORT weekly (Sunday 01:00), LONG monthly (1st of month 02:00)
12. **Media VM** — creates mediastack VM (4 vCPUs, 8GB RAM) with OS disk + downloads disk

---

## Dataset Structure

Naming convention: `<hostname>-<usage>` — always lowercase

```
data/
├── mediastack/                         # Container — no snapshot
│   ├── mediastack-data                 # Dataset — NFS, movies/TV/music/audiobooks
│   │   recordsize=512K, atime=off
│   └── mediastack-downloads            # Zvol 100GB — NZBGet (thin, 16K)
└── vms/                                # Container — no snapshot
    └── mediastack-os                   # Zvol 40GB — Media VM OS disk (thin, 16K)
```

NFS: only `data/mediastack/mediastack-data` → 192.168.10.0/24

---

## Audit

```bash
ansible-playbook ansible/truenas/audit.yml
```

Checks whether more pools, datasets/zvols or NFS shares exist on TrueNAS than defined in `config.yml`. Read-only, no changes.

---

## Configuration

### `vars/config.yml`

```yaml
truenas_url: "https://192.168.10.25"
truenas_validate_certs: false

data_pool_serials:
  - ZW611XR4
  - WD-WCC4N0PU0J03
  - ...
archive_pool_serial: 2327E6EB5451

datasets:
  - name: data/mediastack
    snapshot: false
  - name: data/mediastack/mediastack-data
    recordsize: 512K
    atime: "OFF"

zvols:
  - name: data/vms/mediastack-os
    volsize: 42949672960   # 40GB
    volblocksize: "16K"

nfs_shares:
  - path: /mnt/data/mediastack/mediastack-data
```

### `vars/secrets.yml`

Not in Git. Template: `vars/secrets.yml.example`

```yaml
truenas_api_key: "1-xxxx..."
truenas_vm_vnc_password: "..."
```

---

## Running

```bash
# From repo root
ansible-playbook ansible/truenas/configure.yml
ansible-playbook ansible/truenas/audit.yml
```

The playbook is **idempotent**: running it multiple times is safe.

---

## Known Limitations

- **`xattr` and `dnodesize`** are not supported by `pool.dataset.create` — not configurable via Ansible
- **S.M.A.R.T. schedules** have no midclt endpoint — configure manually in the WebUI
- **GPU passthrough** (P1-15): Ryzen 7 3700X has no iGPU, TrueNAS refuses passthrough of the only GPU as long as no second display output is present

## File Structure

```
ansible/truenas/
├── configure.yml          # Main playbook
├── audit.yml              # Drift detection (read-only)
├── README.md              # This file
├── tasks/
│   └── wipe_disk.yml      # Wipe a single disk
└── vars/
    ├── config.yml         # Configuration (in Git)
    ├── secrets.yml        # Secrets (gitignored)
    └── secrets.yml.example
```
