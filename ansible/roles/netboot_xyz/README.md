# netboot_xyz

Deployt netboot.xyz als Docker-Container und stellt OS-Installer-Configs bereit.

## Voraussetzungen

- Docker + Docker Compose auf dem Ziel-Host
- Ansible-Collection `community.docker`

## Verwendung

```bash
ansible-playbook ansible/vm_netboot.yml
```

## Architektur

```
netboot VM (192.168.10.156)
├── TFTP :69       → netboot.xyz EFI/KPXE + iPXE Menüs (/config/menus/)
├── HTTP :8080     → Kickstart/Answer-Files + lokale Kernel-Images (/assets/)
└── Web  :3000     → netboot.xyz Admin-UI
```

Der Boot-Flow:
1. VM bootet via PXE → DHCP liefert TFTP-Server + Boot-File
2. TFTP liefert `netboot.xyz.efi` (UEFI)
3. netboot.xyz lädt `local-vars.ipxe` → setzt `custom_url=http://192.168.10.156:8080`
4. Hauptmenü zeigt **Custom URL Menu** → lädt `custom.ipxe` via HTTP
5. Auswahl → Kernel + Initrd werden geladen → Installation startet

## Bereitgestellte Configs

| File | OS | Format | Pfad |
|------|----|--------|------|
| `almalinux-answers.ks` | AlmaLinux 9 | Anaconda Kickstart | `/assets/` |
| `pve-answers.toml` | Proxmox VE | Auto-Installer (TOML) | `/assets/` |
| `custom.ipxe` | — | iPXE Menü | `/config/menus/` |

## Lokale Kernel-Images

AlmaLinux 9 Kernel + Initrd werden beim Ansible-Run lokal gecacht:

```
/assets/almalinux9/vmlinuz     (~15MB)
/assets/almalinux9/initrd.img  (~152MB)
```

**Warum lokal?** Die `initrd.img` ist ~150MB. Direktes Laden von einem Remote-Mirror
schlägt mit iPXE häufig fehl (Timeouts, korruptes Archiv).

---

## ⚠️ TrueNAS VMs: PXE-Install aktuell nicht umsetzbar

### Entscheid

PXE-basierte OS-Installation für TrueNAS-VMs (mediastack) wurde nach
ausgiebigem Testing aufgegeben. **Workaround: ISO-Install** (siehe unten).

### Problem: iPXE EFI + grosse Initrd (>100MB)

TrueNAS SCALE VMs booten via UEFI (OVMF). iPXE EFI hat einen bekannten Bug:
das initrd wird von iPXE in den Speicher geladen, aber nicht korrekt an den
Linux-Kernel übergeben. Der Kernel startet ohne initramfs und panikt:

```
Initramfs unpacking failed: invalid magic at start of compressed archive
Kernel panic - not syncing: VFS: Unable to mount root fs on unknown-block(0,0)
```

Bestätigt durch `rd.shell` + `rd.break=pre-udev`: keine Shell erscheint → der
Kernel führt das initramfs nie aus.

### Getestete Workarounds (alle gescheitert)

| Ansatz | Ergebnis |
|--------|----------|
| `initrd --name initrd` + `initrd=initrd` (iPXE named initrd) | Gleiches Problem |
| Initrd lokal servieren statt Remote-Mirror | Gleiches Problem |
| `ip=dhcp` im Kernel-Param | Gleiches Problem |
| UEFI_CSM + `netboot.xyz-undionly.kpxe` (Legacy PXE) | "no bootable device" — VirtIO NIC hat kein BIOS PXE Option-ROM |
| UEFI_CSM + E1000 NIC | nicht getestet |
| GRUB2 EFI (`grubx64.efi` vom AlmaLinux Install-Media) | "Exec format error" — Binary ist nicht standalone, braucht Shim |
| GRUB2 EFI mit Shim (`BOOTX64.EFI`) | nicht erfolgreich |

### Ursache (Analyse)

- TrueNAS SCALE VMs: UEFI (OVMF), VirtIO NIC
- netboot.xyz 3.0.0 / iPXE EFI: bekannte Limitation mit initrd >100MB in EFI-Modus
- VirtIO NIC hat kein BIOS PXE Option-ROM → Legacy-Fallback funktioniert nicht
- GRUB2 vom AlmaLinux Install-Media ist kein Standalone-Binary → braucht Shim + Modules-Verzeichnis

### Workaround: ISO-Install

**AlmaLinux 9 Kickstart via ISO:**

1. ISO herunterladen (auf TrueNAS oder lokal):
   ```
   https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-9-latest-x86_64-minimal.iso
   ```

2. TrueNAS UI → VM → Edit → Device hinzufügen → **CDROM** → ISO auswählen

3. VM starten → ISO bootet in GRUB-Menü → bei "Install AlmaLinux 9" **`e`** drücken

4. An die `linuxefi`-Zeile anhängen:
   ```
   inst.ks=http://192.168.10.156:8080/almalinux-answers.ks
   ```

5. `Ctrl+X` → Kickstart übernimmt, Installation läuft vollautomatisch durch

6. Nach Installation: CDROM-Device aus VM entfernen

Der Kickstart (`almalinux-answers.ks`) ist vollständig konfiguriert und getestet.

---

## OS installieren (PVE via PXE)

PXE-Install für Proxmox funktioniert problemlos (kein grosses initrd, anderer Installer):

1. VM via PXE booten → **Custom URL Menu** → **Proxmox VE 9.1 — Auto-Install**
2. Answer-File enthält IP, Disk, Root-Passwort
3. `netboot_root_password` via Ansible Vault setzen

---

## Bekannte Probleme & Fixes

### custom.ipxe erscheint nicht im Menü

**Ursache:** `local-vars.ipxe` nicht geladen → `custom_url` nicht gesetzt.

**Diagnose:**
```bash
docker logs --tail 50 netbootxyz
```
Erwartete Zeile: `sent /config/menus/local-vars.ipxe to <ip>`

**Häufige Ursachen:**
- `local-vars.ipxe` im falschen Verzeichnis (muss in `/config/menus/`, nicht `/config/`)
- SELinux: Datei nach Container-Start deployed → falsches SELinux-Label →
  `Permission denied` im TFTP-Server. Fix: Ansible deployt Dateien **vor**
  Container-Start, Container-Restart am Ende der Role setzt `:z`-Labels neu.

---

## Nach der Installation

Hostname, weitere Konfiguration etc. per Ansible — nicht im Installer.
```bash
ssh -i ssh/ansible ansible@<ip>
```
