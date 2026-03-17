# vm_base

Basis-Konfiguration für alle AlmaLinux 9 VMs nach der OS-Installation.

## Verwendung

```bash
# Alle VMs einer Gruppe
ansible-playbook ansible/vm_base.yml -e target=mediastack

# Einzelner Host
ansible-playbook ansible/vm_base.yml -e target=mediastack
```

## Was diese Role macht

1. Hostname setzen
2. Basis-Packages installieren: `qemu-guest-agent`, `git`, `curl`, `vim`
3. `qemu-guest-agent` starten + aktivieren
4. `ansible`-User + Gruppe anlegen, SSH-Key hinterlegen, passwordless sudo
5. SSH härten: Password-Auth deaktivieren, Root-Login deaktivieren

## Variablen

| Variable | Default | Beschreibung |
|----------|---------|-------------|
| `ansible_ssh_public_key` | (in defaults) | SSH Public Key für den ansible-User |

## Voraussetzungen

- AlmaLinux 9 frisch installiert
- SSH-Zugang als root (für Bootstrap) oder als ansible-User (für Re-Runs)
- `sshpass` auf dem Control-Node (für initiales Password-Auth Bootstrap)
