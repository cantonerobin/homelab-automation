# mediastack

Richtet den Storage der Mediastack VM ein: Config-Disk und NFS-Mounts von TrueNAS.

## Verwendung

```bash
ansible-playbook ansible/mediastack.yml
```

## Was diese Role macht

1. **Config-Disk** (`/dev/sdb`, Zvol `data/media-config`) mit XFS formatieren (Label `mediastack-config`) und auf `/opt/mediastack` mounten
2. **NFS-Utils** installieren
3. **NFS-Mounts** einrichten:
   - `192.168.10.25:/mnt/data/media-data` → `/mnt/media`
   - `192.168.10.25:/mnt/data/downloads` → `/mnt/downloads`

## Storage-Layout

```
/dev/sda    xfs    /                  50GB  OS-Disk (Zvol data/media-vm)
/dev/sdb    xfs    /opt/mediastack    50GB  Config-Disk (Zvol data/media-config)
                   └── nzbget/tmp          NZBGet temp/entpacken (lokal, kein NFS)
NFS                /mnt/media               TrueNAS data/media-data
NFS                /mnt/downloads           TrueNAS data/downloads
```

## NZBGet-Strategie

Download + Entpacken läuft lokal auf `/opt/mediastack/nzbget/tmp` (kein NFS-Overhead bei intensivem I/O). Fertige Files werden nach `/mnt/downloads` verschoben.

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
