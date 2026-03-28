# mediastack

Sets up storage for the mediastack VM: config disk and NFS mounts from TrueNAS.

## Usage

```bash
ansible-playbook ansible/mediastack.yml
```

## What this role does

1. **nfs-utils** install
2. **NFS mounts** setup:
   - `192.168.10.25:/mnt/data/mediastack/mediastack-data` → `/mnt/media`

## Storage Layout

```
/dev/sda    xfs    /              40GB  OS disk (zvol data/vms/mediastack-os)
/dev/sdb    xfs    /mnt/downloads 100GB downloads disk (zvol data/mediastack/mediastack-downloads)
NFS                /mnt/media           TrueNAS data/mediastack/mediastack-data
```

## NZBGet Strategy

Download + extraction runs directly on `/mnt/downloads` (zvol, no NFS overhead). Finished files stay on the same volume — no transfer needed. Plex reads media via NFS mount `/mnt/media`.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `mediastack_config_disk` | `/dev/sdb` | Block device of the config disk |
| `mediastack_config_label` | `mediastack-config` | XFS label (for stable fstab mount) |
| `mediastack_config_mountpoint` | `/opt/mediastack` | Mount point for the config disk |
| `truenas_ip` | `192.168.10.25` | TrueNAS IP for NFS mounts |
| `nfs_mounts` | (see defaults) | List of NFS mounts (src + mountpoint) |

## Prerequisites

- AlmaLinux 9, `vm_base` role already run
- TrueNAS NFS shares active (`ansible/truenas/configure.yml` run)
- Config disk (`/dev/sdb`) is empty (not yet formatted)
