# TrueNAS Ansible Playbook

Konfiguriert TrueNAS Scale vollständig via REST API (kein SSH auf TrueNAS nötig).
Ausgeführt vom lokalen Control Node (z.B. WSL2).

## API-Versionen und Migrationspfad

Das Playbook nutzt aktuell die **REST API (`/api/v2.0`)**.

| TrueNAS Version | API Status | Playbook-Ansatz |
|-----------------|------------|-----------------|
| < 25.04 | REST v2.0 aktiv | `uri`-Modul, `connection: local` |
| 25.04 | REST v2.0 deprecated (WebUI-Warnung) | Noch funktional |
| **26+** | REST v2.0 **entfernt** | Migration auf `midclt` via SSH notwendig |

### Migration auf TrueNAS 26+

Ab v26 muss das Playbook auf `midclt` via SSH umgebaut werden. `midclt` ist das native CLI-Tool das direkt mit dem TrueNAS Middleware-Daemon spricht — langfristig stabiler als die REST API.

**Bootstrapping (Henne-Ei-Problem bei Neuinstallation):**
SSH ist auf einer frischen TrueNAS-Instanz nicht aktiv. Einmalig manuell aktivieren:
> TrueNAS WebUI → **System → Services → SSH → Start + Autostart aktivieren**
> TrueNAS WebUI → **Credentials → Users → root → SSH Public Keys → ansible.pub einfügen**

Danach übernimmt Ansible vollständig via `midclt`. TrueNAS wird selten neu installiert — dieser einmalige manuelle Schritt ist akzeptabel.

**Method-Namen ändern sich nicht wesentlich** (Slashes → Punkte):
```
POST /api/v2.0/pool/dataset  →  midclt call pool.dataset.create '{...}'
POST /api/v2.0/sharing/nfs   →  midclt call sharing.nfs.create '{...}'
GET  /api/v2.0/disk          →  midclt call disk.query
```

---

## Was das Playbook macht

1. **Disk-Auflösung** — Fragt alle Disks von der API ab und löst konfigurierte Seriennummern in aktuelle Gerätenamen auf (sda/sdb/etc. sind nicht stabil über Reboots)
2. **Disk wipe** — Wischt Disks sauber (QUICK mode) bevor Pools erstellt werden, nur wenn der Pool noch nicht existiert
3. **ZFS Pool `data`** — RAIDZ1 über 4 Disks, erstellt nur wenn noch nicht vorhanden
4. **ZFS Pool `archive`** — Single-Disk STRIPE, erstellt nur wenn noch nicht vorhanden
5. **Datasets** — Erstellt konfigurierte Datasets mit LZ4-Kompression (idempotent: 422 = bereits vorhanden wird ignoriert)
6. **NFS Service** — Startet NFS und aktiviert Autostart beim Boot
7. **NFS Shares** — Erstellt Shares für konfigurierte Pfade, überspringt bereits vorhandene
8. **Snapshot Tasks** — Tägliche Snapshots mit 2 Wochen Retention, einmal pro Dataset
9. **Scrub Tasks** — Wöchentliche Scrubs für beide Pools
10. **S.M.A.R.T. Tests** — ⚠️ Kein API-Endpoint verfügbar (bestätigt via `core.get_methods`). Muss manuell konfiguriert werden: *Data Protection → S.M.A.R.T. Tests → Add*. Empfehlung: SHORT weekly (Sonntag 01:00), LONG monthly (1. des Monats 02:00)
11. **VMs** — Erstellt Media VM (4 cores, 16GB, 50GB) auf TrueNAS

Pool-Erstellung ist asynchron (TrueNAS Job-System). Das Playbook pollt den Job-Status bis Abschluss oder Fehler.

## Voraussetzungen

```bash
# Ansible Collection installieren (requirements.yml)
ansible-galaxy collection install -r ansible/requirements.yml
```

> **Hinweis:** Die `arensb.truenas` Collection ist in `requirements.yml` referenziert, wird aber vom Playbook **nicht genutzt** — alle API-Aufrufe erfolgen via `uri`-Modul direkt gegen die REST API.

## Konfiguration

### `vars/config.yml`

```yaml
truenas_url: "https://192.168.10.73"
truenas_validate_certs: false  # self-signed cert

# Disk-Identifikation über Seriennummern (stabil über Reboots)
data_pool_serials:
  - data01
  - data02
  - data03
  - data04
archive_pool_serial: archive01

nfs_allowed_network: "192.168.10.0/24"

datasets:
  - name: data/media
  - name: data/downloads
  - name: data/backups
  - name: data/nextcloud

nfs_shares:
  - path: /mnt/data/media
  - path: /mnt/data/downloads
  - path: /mnt/data/nextcloud

# VMs — Disk-Pfade als zvols
# Test-VM: data Pool verwenden. Echte Hardware: eigenen vmstore Pool anlegen.
truenas_vm_bridge: br0
media_vm_disk_path: /dev/zvol/data/media
```

**Für echte Hardware:** Seriennummern der Synology-Disks in `data_pool_serials` und `archive_pool_serial` eintragen. Die Seriennummer steht auf dem Disk-Label oder ist über `smartctl -i /dev/sdX` abrufbar.

### `vars/secrets.yml`

Nicht im Git. Vorlage: `vars/secrets.yml.example`

```yaml
truenas_api_key: "1-xxxx..."
```

API Key erstellen: TrueNAS Web UI → **Credentials → API Keys → Add**

## Ausführen

```bash
# Vom Repo-Root
ansible-playbook ansible/truenas/configure.yml
```

Das Playbook ist **idempotent**: Mehrfaches Ausführen ist sicher. Existierende Pools, Shares und Tasks werden übersprungen.

## Test-VM Setup (PVE)

Für Entwicklung und Validierung vor echter Hardware:

1. TrueNAS Scale ISO in PVE hochladen und VM erstellen
2. **CPU Type auf `host` setzen:** `qm set <vmid> --cpu host` (nötig damit TrueNAS eigene VMs laufen lassen kann)
3. **5 virtuelle Disks** hinzufügen (4x für `data` RAIDZ1, 1x für `archive`)
4. Seriennummern setzen (QEMU-Disks haben standardmässig keine Seriennummer, TrueNAS lehnt Pools mit doppelten/leeren Serials ab):

```bash
# Aktuelle Disk-Konfiguration der VM anzeigen
qm config <vmid> | grep scsi

# Seriennummern setzen — auf dem PVE-Host ausführen (VM-ID + Storage/Disk-Pfad anpassen)
qm set <vmid> --scsi0 <storage>:<disk>,serial=os01       # OS Mirror Disk 1
qm set <vmid> --scsi1 <storage>:<disk>,serial=os02       # OS Mirror Disk 2
qm set <vmid> --scsi2 <storage>:<disk>,serial=data01
qm set <vmid> --scsi3 <storage>:<disk>,serial=data02
qm set <vmid> --scsi4 <storage>:<disk>,serial=data03
qm set <vmid> --scsi5 <storage>:<disk>,serial=data04
qm set <vmid> --scsi6 <storage>:<disk>,serial=archive01

# VM neu starten damit TrueNAS die Serials erkennt
qm reboot <vmid>
```

> **Wichtig:** Auch OS-Disks (scsi0/scsi1 für Mirror) brauchen eindeutige Serials. TrueNAS prüft alle Disks — fehlen Serials auf den OS-Disks, schlägt die Pool-Erstellung mit `Duplicate serial numbers: None` fehl.

> **Nach Snapshot-Restore:** Die VM-Konfiguration (inkl. Serials) wird mit dem Snapshot zurückgesetzt. Serials müssen danach erneut gesetzt werden.

5. `vars/config.yml` auf Test-Serials (data01..04, archive01) zeigen lassen — default ist bereits so konfiguriert
6. `vars/secrets.yml` mit Test-VM API Key anlegen

## Dateistruktur

```
ansible/truenas/
├── configure.yml          # Haupt-Playbook
├── README.md              # Diese Datei
├── tasks/
│   └── wipe_disk.yml      # Task-File: Einzelne Disk wipen + auf Job warten
└── vars/
    ├── config.yml         # Konfiguration (im Git)
    ├── secrets.yml        # API Key (gitignored)
    └── secrets.yml.example
```

## Hinweise

- **Pool-Erstellung ist destruktiv** — Disks werden vorher gewischt. Das Playbook prüft zuerst ob der Pool existiert und überspringt Wipe + Erstellung wenn ja.
- **Seriennummern sind Pflicht** für zuverlässige Disk-Identifikation. Ohne stabile Serials können Disk-Namen (sda/sdb) nach einem Reboot andere Disks bezeichnen.
- **`validate_certs: false`** ist für selbstsignierte Zertifikate nötig. Nach TLS-Cert-Deployment (P1-23) auf `true` stellen.
- **Job-Polling:** Pool-Erstellung und Disk-Wipe laufen als TrueNAS-Jobs. Das Playbook pollt `/api/v2.0/core/get_jobs?id=<id>` bis `state` `SUCCESS` oder `FAILED` ist.
