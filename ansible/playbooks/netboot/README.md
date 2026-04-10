# netboot_xyz

Deploys netboot.xyz as a Docker container and provides OS installer configs.

## Prerequisites

- Docker + Docker Compose on the target host
- Ansible collection `community.docker`

## Usage

```bash
ansible-playbook ansible/vm_netboot.yml
```

## Architecture

```
netboot VM (192.168.10.156)
├── TFTP :69       → netboot.xyz EFI/KPXE + iPXE menus (/config/menus/)
├── HTTP :8080     → kickstart/answer files + local kernel images (/assets/)
└── Web  :3000     → netboot.xyz admin UI
```

Boot flow:
1. VM boots via PXE → DHCP provides TFTP server + boot file
2. TFTP delivers `netboot.xyz.efi` (UEFI)
3. netboot.xyz loads `local-vars.ipxe` → sets `custom_url=http://192.168.10.156:8080`
4. Main menu shows **Custom URL Menu** → loads `custom.ipxe` via HTTP
5. Selection → kernel + initrd are loaded → installation starts

## Provided Configs

| File | OS | Format | Path |
|------|----|--------|------|
| `almalinux-answers.ks` | AlmaLinux 9 | Anaconda Kickstart | `/assets/` |
| `pve-answers.toml` | Proxmox VE | Auto-Installer (TOML) | `/assets/` |
| `custom.ipxe` | — | iPXE menu | `/config/menus/` |

## Local Kernel Images

AlmaLinux 9 kernel + initrd are cached locally during the Ansible run:

```
/assets/almalinux9/vmlinuz     (~15MB)
/assets/almalinux9/initrd.img  (~152MB)
```

**Why local?** The `initrd.img` is ~150MB. Loading directly from a remote mirror
frequently fails with iPXE (timeouts, corrupted archive).

---

## ⚠️ TrueNAS VMs: PXE install currently not feasible

### Decision

PXE-based OS installation for TrueNAS VMs (mediastack) was abandoned after
extensive testing. **Workaround: ISO install** (see below).

### Problem: iPXE EFI + large initrd (>100MB)

TrueNAS SCALE VMs boot via UEFI (OVMF). iPXE EFI has a known bug:
the initrd is loaded by iPXE into memory but not correctly handed off to the
Linux kernel. The kernel starts without initramfs and panics:

```
Initramfs unpacking failed: invalid magic at start of compressed archive
Kernel panic - not syncing: VFS: Unable to mount root fs on unknown-block(0,0)
```

Confirmed via `rd.shell` + `rd.break=pre-udev`: no shell appears → the kernel
never executes the initramfs.

### Tested workarounds (all failed)

| Approach | Result |
|----------|--------|
| `initrd --name initrd` + `initrd=initrd` (iPXE named initrd) | Same problem |
| Serve initrd locally instead of remote mirror | Same problem |
| `ip=dhcp` in kernel param | Same problem |
| UEFI_CSM + `netboot.xyz-undionly.kpxe` (legacy PXE) | "no bootable device" — VirtIO NIC has no BIOS PXE option ROM |
| UEFI_CSM + E1000 NIC | not tested |
| GRUB2 EFI (`grubx64.efi` from AlmaLinux install media) | "Exec format error" — binary is not standalone, needs shim |
| GRUB2 EFI with shim (`BOOTX64.EFI`) | not successful |

### Root cause (analysis)

- TrueNAS SCALE VMs: UEFI (OVMF), VirtIO NIC
- netboot.xyz 3.0.0 / iPXE EFI: known limitation with initrd >100MB in EFI mode
- VirtIO NIC has no BIOS PXE option ROM → legacy fallback does not work
- GRUB2 from AlmaLinux install media is not a standalone binary → needs shim + modules directory

### Workaround: ISO install

**AlmaLinux 9 Kickstart via ISO:**

1. Download ISO (on TrueNAS or locally):
   ```
   https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-9-latest-x86_64-minimal.iso
   ```

2. TrueNAS UI → VM → Edit → Add device → **CDROM** → select ISO

3. Start VM → ISO boots into GRUB menu → press `e` at "Install AlmaLinux 9"

4. Append to the `linuxefi` line:
   ```
   inst.ks=http://192.168.10.156:8080/almalinux-answers.ks
   ```

5. `Ctrl+X` → kickstart takes over, installation runs fully automated

6. After installation: remove CDROM device from VM

The kickstart (`almalinux-answers.ks`) is fully configured and tested.

---

## Install OS (PVE via PXE)

PXE install for Proxmox works without issues (no large initrd, different installer):

1. Boot VM via PXE → **Custom URL Menu** → **Proxmox VE 9.1 — Auto-Install**
2. Answer file contains IP, disk, root password
3. Set `netboot_root_password` via Ansible Vault

---

## Known Issues & Fixes

### custom.ipxe does not appear in the menu

**Cause:** `local-vars.ipxe` not loaded → `custom_url` not set.

**Diagnose:**
```bash
docker logs --tail 50 netbootxyz
```
Expected line: `sent /config/menus/local-vars.ipxe to <ip>`

**Common causes:**
- `local-vars.ipxe` in the wrong directory (must be in `/config/menus/`, not `/config/`)
- SELinux: file deployed after container start → wrong SELinux label →
  `Permission denied` in TFTP server. Fix: Ansible deploys files **before**
  container start, container restart at the end of the role resets `:z` labels.

---

## After Installation

Hostname, further configuration etc. via Ansible — not in the installer.
```bash
ssh -i ssh/ansible ansible@<ip>
```
