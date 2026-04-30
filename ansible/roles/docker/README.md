# docker_host

Installs Docker CE + Docker Compose Plugin and sets up a shared compose directory.

## Usage

```bash
ansible-playbook ansible/vm_netboot.yml   # uses this role via vm_netboot
```

Or directly in a playbook:

```yaml
roles:
  - vm_base
  - docker_host
```

## What this role does

1. Add Docker CE repository
2. Install `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-compose-plugin`
3. Start + enable Docker
4. Add configured user(s) to the `docker` group
5. Create compose directory (`/opt/docker`)

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `docker_compose_dir` | `/opt/docker` | Directory for Docker Compose projects |
| `docker_users` | `[ansible]` | Users to add to the docker group |

## Prerequisites

- AlmaLinux 9
- `vm_base` role already run (ansible user exists)
