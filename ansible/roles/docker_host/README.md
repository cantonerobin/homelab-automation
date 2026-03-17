# docker_host

Installiert Docker CE + Docker Compose Plugin und richtet ein gemeinsames Compose-Verzeichnis ein.

## Verwendung

```bash
ansible-playbook ansible/vm_netboot.yml   # nutzt diese Role via vm_netboot
```

Oder direkt in einem Playbook:

```yaml
roles:
  - vm_base
  - docker_host
```

## Was diese Role macht

1. Docker CE Repository hinzufügen
2. `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-compose-plugin` installieren
3. Docker starten + aktivieren
4. Konfigurierten User(s) zur `docker`-Gruppe hinzufügen
5. Compose-Verzeichnis anlegen (`/opt/docker`)

## Variablen

| Variable | Default | Beschreibung |
|----------|---------|-------------|
| `docker_compose_dir` | `/opt/docker` | Verzeichnis für Docker Compose Projekte |
| `docker_users` | `[ansible]` | User die zur docker-Gruppe hinzugefügt werden |

## Voraussetzungen

- AlmaLinux 9
- `vm_base` Role bereits ausgeführt (ansible-User existiert)
