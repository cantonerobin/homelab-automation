# TrueNAS Ansible Playbook

Konfiguriert TrueNAS Scale vollständig via SSH + `midclt`.
Ausgeführt vom lokalen Control Node (z.B. WSL2).

## Bootstrapping (einmalig manuell)

SSH ist auf einer frischen TrueNAS-Instanz nicht aktiv. Einmalig manuell aktivieren:
> TrueNAS WebUI → **System → Services → SSH → Start + Autostart aktivieren**
> TrueNAS WebUI → **Credentials → Users → root → SSH Public Keys → ansible.pub einfügen**

Danach übernimmt Ansible vollständig via `midclt`.

---

## Was das Playbook macht

1. **Disk-Auflösung** — Löst konfigurierte Seriennummern in aktuelle Gerätenamen auf (sda/sdb/etc. sind nicht stabil über Reboots)
2. **Disk wipe** — Wischt Disks sauber (QUICK mode) bevor Pools erstellt werden, nur wenn der Pool noch nicht existiert
3. **ZFS Pool `data`** — RAIDZ1 über 4 Disks, erstellt nur wenn noch nicht vorhanden
4. **ZFS Pool `archive`** — Single-Disk STRIPE, erstellt nur wenn noch nicht vorhanden
5. **Datasets** — Erstellt konfigurierte Datasets mit Properties (compression, recordsize, atime). Idempotent: bestehende Datasets werden aktualisiert.
6. **Zvols** — Erstellt VM-Disks als thin-provisioned Zvols (`sparse=true`, `volblocksize=16K`)
7. **NFS Service** — Startet NFS und aktiviert Autostart beim Boot
8. **NFS Shares** — Erstellt Shares für konfigurierte Pfade, überspringt bereits vorhandene
9. **Snapshot Tasks** — Tägliche Snapshots mit 2 Wochen Retention (nur Datasets mit `snapshot: true`)
10. **Scrub Tasks** — Monatliche Scrubs für beide Pools (1. des Monats)
11. **S.M.A.R.T. Tests** — ⚠️ Kein midclt-Endpoint verfügbar. Manuell konfigurieren: *Data Protection → S.M.A.R.T. Tests → Add*. Empfehlung: SHORT weekly (Sonntag 01:00), LONG monthly (1. des Monats 02:00)
12. **Media VM** — Erstellt mediastack VM (4 vCPUs, 8GB RAM) mit OS-Disk + Downloads-Disk

---

## Dataset-Struktur

Namenskonvention: `<hostname>-<verwendung>` — immer lowercase

```
data/
├── mediastack/                         # Container — kein Snapshot
│   ├── mediastack-data                 # Dataset — NFS, Filme/Serien/Musik/Audiobooks
│   │   recordsize=512K, atime=off
│   └── mediastack-downloads            # Zvol 100GB — NZBGet (thin, 16K)
└── vms/                                # Container — kein Snapshot
    └── mediastack-os                   # Zvol 40GB — Media VM OS-Disk (thin, 16K)
```

NFS: nur `data/mediastack/mediastack-data` → 192.168.10.0/24

---

## Audit

```bash
ansible-playbook ansible/truenas/audit.yml
```

Prüft ob mehr Pools, Datasets/Zvols oder NFS-Shares auf TrueNAS existieren als in `config.yml` definiert. Nur lesend, keine Änderungen.

---

## Konfiguration

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

Nicht im Git. Vorlage: `vars/secrets.yml.example`

```yaml
truenas_api_key: "1-xxxx..."
truenas_vm_vnc_password: "..."
```

---

## Ausführen

```bash
# Vom Repo-Root
ansible-playbook ansible/truenas/configure.yml
ansible-playbook ansible/truenas/audit.yml
```

Das Playbook ist **idempotent**: Mehrfaches Ausführen ist sicher.

---

## Bekannte Einschränkungen

- **`xattr` und `dnodesize`** werden von `pool.dataset.create` nicht unterstützt — nicht konfigurierbar via Ansible
- **S.M.A.R.T.-Schedules** haben keinen midclt-Endpoint — manuell in der WebUI konfigurieren
- **GPU-Passthrough** (P1-15): Ryzen 7 3700X hat keine iGPU, TrueNAS verweigert Passthrough der einzigen GPU solange kein zweiter Display-Output vorhanden

## Dateistruktur

```
ansible/truenas/
├── configure.yml          # Haupt-Playbook
├── audit.yml              # Drift-Detection (nur lesend)
├── README.md              # Diese Datei
├── tasks/
│   └── wipe_disk.yml      # Einzelne Disk wipen
└── vars/
    ├── config.yml         # Konfiguration (im Git)
    ├── secrets.yml        # Secrets (gitignored)
    └── secrets.yml.example
```
