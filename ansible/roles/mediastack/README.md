# mediastack

Richtet den Storage der Mediastack VM ein: Config-Disk und NFS-Mounts von TrueNAS.

## Verwendung

```bash
ansible-playbook ansible/mediastack.yml
```

## Was diese Role macht

1. **NFS-Utils** installieren
2. **NFS-Mounts** einrichten:
   - `192.168.10.25:/mnt/data/mediastack/mediastack-data` → `/mnt/media`

## Storage-Layout

```
/dev/sda    xfs    /              40GB  OS-Disk (Zvol data/vms/mediastack-os)
/dev/sdb    xfs    /mnt/downloads 100GB Downloads-Disk (Zvol data/mediastack/mediastack-downloads)
NFS                /mnt/media           TrueNAS data/mediastack/mediastack-data
```

## NZBGet-Strategie

Download + Entpacken läuft direkt auf `/mnt/downloads` (Zvol, kein NFS-Overhead). Fertige Files liegen auf demselben Volume — kein Transfer nötig. Plex liest Media via NFS-Mount `/mnt/media`.

## Variablen

| Variable | Default | Beschreibung |
|----------|---------|-------------|
| `mediastack_config_disk` | `/dev/sdb` | Block-Device der Config-Disk |
| `mediastack_config_label` | `mediastack-config` | XFS-Label (für stabilen fstab-Mount) |
| `mediastack_config_mountpoint` | `/opt/mediastack` | Mountpoint der Config-Disk |
| `truenas_ip` | `192.168.10.25` | TrueNAS IP für NFS-Mounts |
| `nfs_mounts` | (siehe defaults) | Liste der NFS-Mounts (src + mountpoint) |

## Voraussetzungen

- AlmaLinux 9, `vm_base` Role bereits ausgeführt
- TrueNAS NFS-Shares aktiv (`ansible/truenas/configure.yml` ausgeführt)
- Config-Disk (`/dev/sdb`) ist leer (noch nicht formatiert)
