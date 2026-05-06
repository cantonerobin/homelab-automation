# Homelab — Roadmap

> Phases and tasks to get from the current state (`current.md`) to the target state (`target.md`).
> Last updated: 2026-04-24

---

## Legend
- ✅ Done
- 🔄 In progress
- ⚠️ Blocked / open issue
- ❌ Pending
- ❓ Decision pending

---

## Phase 0 — Preparation

| # | Task | Status | Note |
|---|------|--------|-------|
| P0-1 | Remove SSH private key from Git history (`git filter-repo`) | ✅ | Done |
| P0-2 | Generate new SSH keypair for Ansible | ✅ | Done |
| P0-3 | Remove `cipassword = "test123"` from `vm_k3s.tf` | ✅ | Done |
| P0-5 | Deploy netboot.xyz VM (`terraform apply`) | ✅ | Deployed on one of the small nodes |
| P0-6 | Configure Unifi DHCP Option 66/67 for netboot.xyz | ✅ | Done — DHCP provides TFTP server + filename to PXE clients |
| P0-7 | Static IPs for k3s VMs via Cloud-Init | ✅ | VLAN 10: .10/.11/.12, GW .1 |
| P0-8 | Populate Ansible inventory (IPs for k3s-nova/helix/vega) | ✅ | PVE nodes + k3s VMs added |
| P0-9 | Export LXC configurations → `docs/current.md` | ✅ | Docker-Composes in `docs/legacy/docker-compose/` ✅ — IPs + ports documented |
| P0-10 | Document network diagram | ✅ | Integrated in `docs/current.md` (current) + `docs/target.md` (target) |
| P0-11 | Service inventory (ports, DNS, dependencies) | ✅ | Documented incrementally during k3s service setup (Phase 3) — current.md covers existing services |
| P0-12 | Create `k3s-manifests` Git repo | ✅ | Entscheidung: Monorepo — Manifeste in `k3s/` in homelab-automation. Kein separates Repo. |
| P0-13 | Set up Ansible folder structure in repo | ✅ | `proxmox/`, `truenas/`, `k3s/` |
| P0-14 | Migrate Ansible playbooks from another Git repo into `homelab-automation` | ✅ | All relevant playbooks migrated |
| P0-15 | Centralise SSH keypair in `ssh/` (repo root) | ✅ | `ssh/ansible.pub` (committed), `ssh/ansible` (gitignored). Terraform + Ansible reference the same key. `ansible/ansible.cfg` created with `private_key_file` |

---

## Phase 1 — TrueNAS Migration

**Prerequisites:** P0-9 (LXC docs)

| # | Task | Status | Note |
|---|------|--------|-------|
| P1-0 | Mediastack VM: back up configs + data for migration to TrueNAS | ✅ | Done |
| P1-1 | Evacuate Ceph OSDs from orion (`ceph osd out`) | ✅ | Done |
| P1-2 | Wait for Ceph rebalancing (HEALTH_OK) | ✅ | Done |
| P1-3 | Remove orion from PVE cluster (`pvecm delnode`) | ✅ | Done |
| P1-4 | Synology data → back up to external HDD (`rsync`) | ✅ | 3.4TB backed up, size + rsync dry-run verified |
| P1-5 | Install TrueNAS Scale on orion (2x 250GB SSD mirror) | ✅ | Running at 192.168.10.25 |
| P1-6 | Remove Synology disks → install in TrueNAS | ✅ | 4x 3TB HDD + 1x 2TB SSD (Crucial BX500) installed |
| P1-7 | Create ZFS pool `data`: 4x 3TB RAIDZ1 | ✅ | Via Ansible playbook |
| P1-8 | Create ZFS pool `archive`: 1x 2TB SSD (Crucial BX500) | ✅ | Via Ansible playbook |
| P1-9 | L2ARC: add 1x 1TB SSD | ❌ | Dropped — no free drive bay available |
| P1-10 | Create datasets + zvols | ✅ | Via Ansible playbook — `data/mediastack`, `data/mediastack/mediastack-config`, `data/mediastack/mediastack-data`, `data/vms`. Zvols: `mediastack-os` (90GB), `mediastack-downloads` (250GB), `mediastack-plexdb` (80GB) |
| P1-11 | Restore data: external HDD → TrueNAS `data` pool | ✅ | ~4.5TB complete. Snapshots active again. |
| P1-12 | Configure NFS shares | ✅ | Via Ansible playbook — `mediastack-config` + `mediastack-data`, both hosts allowed: 192.168.10.62 + 192.168.30.62 |
| P1-32 | Move mediastack VM + NPM to DMZ (VLAN 30) | ✅ | mediastack: 192.168.30.62 on br30. NPM: 192.168.30.75. TrueNAS DMZ IP: 192.168.30.25 on br30. NFS stays local. |
| P1-14 | TrueNAS VM: set up mediastack VM (8 vCPUs, 16GB, 90GB OS + 250GB downloads + 80GB Plex DB) | ✅ | VM created via Ansible — OS install via PXE pending (P1-28) |
| P1-15 | Configure GPU passthrough in TrueNAS (mediastack VM) | ⚠️ | Deferred — GTX 970 installed in TrueNAS, but GPU passthrough not yet configured. Plex runs without HW-transcoding. |
| P1-16 | Install Plex in mediastack VM | ✅ | Done — running on TrueNAS VM, NFS mounted |
| P1-17 | Install NZBGet in mediastack VM | ✅ | Done — running on TrueNAS VM |
| P1-19 | Create TrueNAS test VM on PVE (TrueNAS Scale ISO, virtual disks) | ✅ | Test VM running (ID 2018, IP 192.168.10.73) — disks with serials configured via `qm set` |
| P1-20 | Ansible playbook: develop + validate TrueNAS configuration against test VM | ✅ | `ansible/truenas/configure.yml` — pools, datasets, NFS, snapshot tasks, scrub tasks. Fully via REST API (`uri`), serial-based disk detection. Successfully validated against test VM. |
| P1-21 | Apply Ansible playbook to real TrueNAS hardware | ✅ | Successfully applied to 192.168.10.25. Pools, datasets, zvols, NFS, snapshots, scrubs, VMs, network configured. |
| P1-22 | Ansible playbook: validate TrueNAS API endpoints | ✅ | Implicitly via P1-21 — midclt-based, all endpoints functional. Integer typing fixes for volsize + vm-ID were necessary. |
| P1-23 | Ansible playbook: configure network | ✅ | Hostname, static IP, gateway, DNS via `midclt call network.configuration.update` + `interface.update`. Adjust IP in `vars/config.yml` before running. |
| P1-24 | Ansible playbook: deploy TLS certificate via Step-CA | ✅ | Implemented in `configure.yml` — CSR (ID 4) + ACME cert via Step-CA DNS-01 (Cloudflare authenticator). Active UI cert: `truenas-acme` (ID 5, valid 1 year). Note: TrueNAS only supports DNS-01, not HTTP-01. |
| P1-25 | Ansible playbook: Step-CA root cert → TrueNAS trust store | ✅ | Implemented in `configure.yml` — root cert to system trust store via `update-ca-certificates`. Note: `certificateauthority.query/create` do not exist in this TrueNAS version — system trust store is sufficient. |
| P1-26 | TrueNAS alert relay → Gotify | ✅ | Script `truenas-alert-monitor.sh` deployed via `monitoring.yml`. Relays TrueNAS native alerts (`alert.list`) + cloud sync failures (`cloudsync.query`) to Gotify every 5 min. Config: `MIN_ALERT_LEVEL`, `IGNORED_ALERT_CLASSES` at top of script. Token: `alert_monitor_gotify_token` in `secrets.yml` (TODO: fill in). |
| P1-27 | Document dataset configuration | ✅ | Documented in `ansible/truenas/README.md` + `docs/current.md` (recordsize, compression, zvol sizes per dataset) |
| P1-28 | Install mediastack VM via netboot.xyz | ✅ | Done — OS installed via netboot.xyz |
| P1-29 | Set up TrueNAS cloud sync: rclone → Hetzner Storage Box | ✅ | Playbook `ansible/truenas/cloudsync.yml`. Encrypted via rclone crypt, scheduled Sunday 02:00. SSH key: `ssh/truenas-hetzner`. Fixed 2026-04-24: remote path had leading slash `/backups/mediastack-config` → Hetzner SFTP treats home as root, SSH_FX_FAILURE on mkdir. Fixed to relative path `backups/mediastack-config` via `midclt call cloudsync.update 5 '{"attributes": {"folder": "backups/mediastack-config"}}'`. Encrypted files confirmed on Hetzner. Restore path: see `docs/learnings.md` (rclone crypt restore procedure). |
| P1-30 | ~~Set up Nextcloud AIO VM on PVE~~ | ➡️ verschoben | **Entscheidung 2026-04-26:** Kein Interim-Setup auf PVE — Nextcloud direkt auf k3s (POC-5 / P3-23). Spart doppelte Einrichtung. Stattdessen: `data/nextcloud` Dataset + NFS Share auf TrueNAS anlegen + alte Daten von ext. HDD (`/dev/sdh`) direkt dorthin rsynen, damit HDD für P1-31 freigegeben werden kann. ⚠️ HDD noch nicht formatieren bis rsync abgeschlossen! |
| P1-31 | Configure external HDD as ZFS pool `external` (PBS + replication) | ❌ | **Depends on Nextcloud k3s produktiv + getestet (P3-23).** HDD wird erst formatiert wenn Nextcloud auf k3s läuft und Daten verifiziert sind — HDD bleibt bis dahin als Fallback. Format HDD as single-disk ZFS pool. Datasets: `external/pbs` (NFS share → PBS VM datastore on PVE), `external/replication` (ZFS replication target from `data` pool). |

---

## Phase 1.5 — Network & DNS Infrastructure

**Prerequisites:** Phase 1 complete
**Goal:** Proper network segmentation before PVE rebuild and k3s. VPN access first — required for safe admin access after firewall rules are active.

**Pi placement:**
- **Final target:** Management VLAN (192.168.1.0/24) — ✅ already wired via switch_tv (ports 7+8, Native VLAN Management). pi01 = 192.168.1.2, pi02 = 192.168.1.3.
- **WiFi:** not suitable — DNS requires stable wired connection.

| # | Task | Status | Note |
|---|------|--------|-------|
| P1.5-0 | Buy switch for Management VLAN wired connection (Pis) | ✅ | Unifi US-8-60W PoE installed as main switch (2026-04-22, replaces old 5-port Lite). Pis on switch_tv ports 7+8 (Native VLAN Management/VLAN 1). |
| P1.5-1 | Flash SD cards + install Raspberry Pi OS Lite (64-bit) on both Pis | ✅ | pi01 (192.168.1.2) + pi02 (192.168.1.3) — directly in Management VLAN, no Untrust interim needed. |
| P1.5-2 | Add Pis to Ansible inventory + verify SSH access | ✅ | Static IPs in inventory: pi01=192.168.1.2, pi02=192.168.1.3 |
| P1.5-3 | Ansible playbook: install AdGuard Home on Pi 1 (primary) | ✅ | `ansible/pi/adguard.yml` — upstream DoT (Cloudflare+Quad9), local DNS rewrites, filter lists. AdGuard Home Sync (Pi01→Pi02) via adguardhome-sync v0.9.0 als systemd-Service auf Pi01. |
| P1.5-4 | Ansible playbook: install AdGuard Home on Pi 2 (secondary) | ✅ | Selbes Playbook — Config via adguardhome-sync von Pi01 synchronisiert (alle 30 Min). |
| P1.5-5 | VPN remote access | ✅ | Covered by Unifi Teleport (WireGuard) — already in place, no dedicated VPN server needed. Tailscale rejected (external auth — KO criterion, must be fully self-hosted). |
| P1.5-6 | Migrate Pis to Management VLAN (wired) | ✅ | DHCP reservations 192.168.1.x, Ansible inventory updated, Unifi DHCP DNS set for all networks. |
| P1.5-7 | Configure router/DHCP: both Pi IPs as DNS servers for all networks | ✅ | Pi01 (192.168.1.2) + Pi02 (192.168.1.3) set as DNS in all Unifi networks. Done as part of P1.5-6. |
| P1.5-8 | Enable VLAN-aware bridge on PVE nodes + assign VLAN tags to VMs | ✅ | Done during Phase 2 reinstall — vmbr0 VLAN-aware, SDN VNETs configured. |
| P1.5-9 | Move PVE management interfaces to VLAN 1 | ✅ | Done 2026-04-30 — helix=192.168.1.10, nova=192.168.1.11, vega=192.168.1.12. Terraform + Ansible inventory updated. |
| P1.5-10 | Implement inter-VLAN firewall rules in Unifi Dream Machine | ❌ | Regelwerk definiert (2026-04-30) — manuell im Unifi UI einrichten. Unifi Global Inter-VLAN Block + 5 Allow-Regeln. Siehe `docs/target.md` (Inter-VLAN Firewall). VLAN 5 (k3s Cluster, 192.168.5.0/24) muss zuerst in Unifi angelegt werden. |

---

## Phase 2 — PVE Cluster Rebuild (Rolling)

**Prerequisites:** P0-5 (netboot.xyz reachable)
**Note:** Ceph will be removed. helix Ceph OSD already evicted (2026-04-24). Nova + vega OSDs removed during their respective rebuilds.
**Storage after Phase 2:** helix + nova — Samsung 256GB only (Kingston dead/worn, no replacement purchased). Vega — WD 1TB becomes local-lvm.
**Order: helix first** — Ceph OSD already gone, Kingston dead. Nova second (86% worn Kingston). Vega last (WD healthy).

*Repeat for each of the 3 nodes (helix → nova → vega):*

| # | Task | Status | Note |
|---|------|--------|-------|
| P2-D1 | ❓ ENTSCHEIDUNG: CIS Level 1 Hardening für AlmaLinux VMs | ✅ | Entschieden 2026-04-30: OpenSCAP post-install (cloud-init) mit CIS L1 Profil. In `build-template.sh` implementiert. |
| P2-0 | Update AlmaLinux VM template — CIS L1 + Node Exporter | ✅ | `build-template.sh` aktualisiert: openscap-scanner + scap-security-guide, CIS L1 oscap remediation, node_exporter v1.8.2 als systemd service (Port 9100). ⚠️ Template muss noch auf PVE neu gebaut werden (build-template.sh -f auf helix). |

> **P2-D1 — Entscheidungsdetails CIS Level 1:**
>
> **Pfad A — Kickstart (TrueNAS-VMs via netboot.xyz):** `%addon org_fedora_oscap` mit `profile = xccdf_org.ssgproject.content_profile_cis_server_l1` in `ansible/playbooks/netboot/templates/almalinux-answers.ks.j2`. ⚠️ Partition-Layout muss angepasst werden: CIS verlangt separate LVs für `/var`, `/var/log`, `/var/log/audit`, `/tmp`, `/home`.
>
> **Pfad B — Cloud-Init-Template (k3s-VMs auf PVE):** Kein „during install" möglich — GenericCloud-Image ist bereits fertig installiert. Hardening via Ansible post-provisioning (`openscap-scanner` + SCAP Security Guide). ⚠️ Tailored Profile erforderlich — folgende Regeln kollidieren direkt mit k3s: `net.ipv4.ip_forward=1` (k3s braucht es), `bridge-nf-call-iptables`, keine separate `/var`-Partition (k3s schreibt stark nach `/var/lib/rancher`).
>
> **Optionen:** (a) Nur Pfad A (TrueNAS-VMs), (b) Pfad A + Pfad B mit tailored Profile, (c) Pfad B ohne CIS (k3s-Nodes bleiben ungehärtet).

| P2-0a | Apply Samsung APST fix on nova (before Phase 2 or during) | ✅ | Applied via `configure.yml` --tags grub. |
| P2-1 | Ansible playbook: PVE node configuration | ✅ | `ansible/playbooks/proxmox/configure.yml` — repos, packages, GRUB/APST, unattended-upgrades, SSH hardening, fail2ban, UFW. Angewendet auf alle 3 Nodes. |
| P2-1a | Ansible playbook: unattended security updates on PVE nodes | ✅ | Teil von configure.yml --tags security. |
| P2-2 | [nova] Ensure backup of all VMs/LXCs on nova | ✅ | Alle VMs/LXCs auf helix migriert 2026-04-29. |
| P2-3 | [nova] Migrate VMs/LXCs to helix/vega | ✅ | Alle auf helix local-lvm migriert. |
| P2-4 | [nova] Remove Ceph OSD + wait for rebalancing | ✅ | |
| P2-5 | [nova] Remove node from cluster | ✅ | |
| P2-6 | [nova] Reinstall PVE via netboot.xyz | ✅ | PVE 9.1.1 / Debian Trixie, 192.168.1.11. |
| P2-7 | [nova] Re-add node to cluster (`pvecm add`) | ✅ | |
| P2-8 | [nova] Configure storage | ✅ | Samsung 256GB als OS + local-lvm. Kingston (86% worn) ungenutzt. |
| P2-9 | [nova] Ansible: configure PVE node | ✅ | configure.yml angewendet. |
| P2-10 | [helix] — same steps as nova | ✅ | Helix war erste Node — Samsung 256GB OS+local-lvm, Kingston disconnected. |
| P2-11 | [vega] — same steps as nova | ✅ | PVE 9.1.1, 192.168.1.12. WD 1TB ungenutzt (für local-lvm vor k3s evaluieren). |
| P2-12 | Migrate k3s VMs from `ceph_data` to local-lvm | ✅ | k3s VMs während Phase 2 gelöscht — werden via Terraform neu provisioniert (Phase 3). Terraform storage auf local-lvm aktualisiert. |
| P2-13 | Fully uninstall Ceph (`pveceph purge` on last node) | ✅ | Ceph vollständig entfernt 2026-04-30. |

---

## Phase POC — Proof of Concept

**Timing:** Parallel to / directly after Phase 3 bootstrap (P3-4/P3-5)

> PoCs require a running k3s cluster — therefore de facto early Phase 3.
> POC-1 is the exception: before Phase 2.

| # | Task | Status | Go/No-Go Criterion |
|---|------|--------|-------------------|
| POC-1 | netboot.xyz: test booting PVE installer over network | ❌ | Before Phase 2 — PVE installer appears, network boot stable |
| POC-3 | NFS Subdir Provisioner: create/delete PVC, test pod restart | ❌ | Before P3-12 — requires k3s cluster (after P3-5). No data loss, mount stable |
| POC-4 | Longhorn: deploy, configure backup target on TrueNAS NFS, test failover | ❌ | Before P3-13 — requires k3s cluster (after P3-5). Decision (hybrid) made, PoC validates implementation |
| POC-5 | Nextcloud PoC: Helm chart + Postgres (Longhorn) + data storage TrueNAS NFS | ❌ | Depends on POC-3+POC-4 + P1-12. Go: migration P3-23. No-Go: AIO stays on TrueNAS VM |

---

## Phase 3 — k3s Cluster

**Prerequisites:** Phase 1 complete (NFS via P1-12)

| # | Task | Status | Note |
|---|------|--------|-------|
| P3-1 | Resolve network issue in k3s VMs (`ip addr`) | ✅ | Resolved via Terraform provider update — bug in provider combined with `user`-config |
| P3-2 | Verify static IPs in VMs | ✅ | Depends on P3-1 |
| P3-2a | Terraform: k3s VMs — 3 NICs + second virtio disk | ❌ | **NICs:** eth0=VLAN5 (Cluster, 192.168.5.x), eth1=VLAN10 (Server, existing IPs), eth2=VLAN30 (DMZ). **Disk:** second virtio 100GB for Longhorn on `/var/lib/longhorn`. Requires VLAN 5 in Unifi + trunk ports on PVE nodes (VLAN 5 freischalten). |
| P3-3 | Ansible playbook: format second disk + mount on `/var/lib/longhorn` | ❌ | Run before k3s install — Longhorn detects the directory automatically |
| P3-4 | Ansible playbook: install k3s server on k3s-nova (`--cluster-init`) | ❌ | `ansible/k3s/` — first node, initialises embedded etcd |
| P3-5 | Ansible playbook: install k3s server on k3s-helix + k3s-vega (`--server`) | ❌ | All 3 nodes are server nodes — HA control plane |
| P3-6 | Make kubeconfig available locally | ❌ | |
| P3-7 | Structure `k3s/` directory (bootstrap/, infrastructure/, apps/) | ✅ | Monorepo in homelab-automation. bootstrap/ + infrastructure/ Unterordner angelegt. apps/ leer bis Phase 3. |
| P3-8 | Deploy and configure ArgoCD | ❌ | App-of-Apps pattern |
| P3-8a | Deploy kube-prometheus-stack (Prometheus + Grafana + Alertmanager) | ❌ | Via ArgoCD. Scrapes Node Exporter (port 9100, baked into template via P2-0) + kube-state-metrics + kubelet. Deploy early — monitoring before complex services. |
| P3-8b | Configure Alertmanager → Gotify | ❌ | Webhook receiver. Alerts on: CrashLoopBackOff, node memory/disk pressure, PVC near full |
| P3-8c | Import Grafana dashboards | ❌ | Node Exporter Full (ID 1860), k3s cluster overview |
| P3-9 | Deploy Traefik als k3s Ingress Controller (via ArgoCD) | ❌ | Ersetzt ingress-nginx — Entscheidung 2026-04-27. Traefik ist k3s-Default, cleaner ForwardAuth für Authentik. k3s mit `--disable=traefik` starten, dann via Helm/ArgoCD selbst managen. |
| P3-10 | Deploy cert-manager + Step-CA integration | ❌ | cert-manager via ACME against existing Step-CA LXC — Step-CA stays as LXC for now |
| P3-11 | Deploy Sealed Secrets | ❌ | ⚠️ Back up cluster key after deploy (TrueNAS) — without key, SealedSecrets cannot be decrypted during cluster rebuild |
| P3-12 | Deploy NFS Subdir Provisioner | ❌ | Depends on Phase 1 P1-12 |
| P3-13 | Deploy Longhorn (via ArgoCD) | ❌ | For: DBs, stateful apps (RWO, replicated across 3 nodes) |
| P3-14 | Configure Longhorn backup target → TrueNAS NFS | ❌ | Depends on P3-13 + P1-12. Longhorn backups are carried along via TrueNAS cloud sync (P1-28) to Hetzner |
| P3-15 | Deploy Authentik (SSO) | ❌ | Deploy early. Connect: Nextcloud, Firefly III, Homepage, Uptime Kuma, Arr-services, Grafana (when monitoring comes). Do NOT connect: Proxmox, TrueNAS, ArgoCD, Longhorn UI (infra tools, VPN-only) |
| P3-16 | Cloudflare DynDNS → k3s | ❌ | Priority: High |
| P3-17 | Homepage → k3s | ❌ | Priority: High |
| P3-18 | Uptime Kuma → k3s | ❌ | Priority: High |
| P3-19 | Gotify → k3s | ❌ | Priority: Medium |
| P3-20 | DMZ Reverse Proxy aufsetzen + NPM ablösen | ❌ | **Tool noch offen** (nginx/Caddy/HAProxy — eigenständige Instanz, nicht k3s). Sitzt vor k3s (Traefik) UND vor non-k3s Services (TrueNAS VM, HomeAssistant etc.). **HA: 2 Instanzen** (je eine LXC/VM auf nova + vega) + Keepalived/VRRP mit VIP im DMZ-Range. Ansible deployt beide identisch (kein Runtime-Sync nötig). Cutover: koordinierter Switch aller DNS/Cloudflare-Einträge von NPM auf VIP. |
| P3-21 | Step-CA → k3s (PKI migration!) | ❌ | Priority: Medium, critical state |
| P3-22 | Set up Nextcloud AIO on PVE VM (interim solution) | ❌ | Moved forward → P1-30 (done in Phase 1, no k3s dependency). VM on PVE, data on TrueNAS NFS. |
| P3-23 | Migrate Nextcloud → k3s (after validated POC-5) | ❌ | Helm chart + Postgres (Longhorn) + NFS dataset (stays). Depends on POC-5 success |
| P3-24 | Deploy Firefly III | ❌ | |
| P3-25 | Set up HomeAssistant VM (PVE) with USB passthrough | ❌ | Zigbee stick, not k3s — dev VM already running (10.61), prod setup with USB passthrough pending |
| P3-26 | Deploy GitLab self-hosted | ❌ | Only when Phase 3 is stable |
| P3-27 | Set up GitLab push mirror: self-hosted → GitLab.com | ❌ | Automatic offsite backup of all repos on every commit. Transition period: GitHub until GitLab self-hosted is running |

---

## Phase E — Elastic Observability Stack

**Prerequisites:** TrueNAS running, netboot.xyz available (P0-5)  
**Motivation:** Elastic Certified Observability Engineer cert prep + homelab observability

| # | Task | Status | Note |
|---|------|--------|-------|
| PE-0 | Make ZFS ARC persistent on TrueNAS | ❌ | `midclt call system.advanced.update '{"arc_max": 25769803776}'` — currently only set temporarily via sysfs, lost on reboot. Do before adding Elastic VM. |
| PE-1 | Add Elastic VM zvols to TrueNAS config | ❌ | `data/vms/elastic-os` (50GB) + `data/vms/elastic-data` (200GB) in `config.yml`, run `configure.yml` |
| PE-2 | Create Elastic VM via Ansible | ❌ | 4 vCPUs, 16GB RAM, br1 (VLAN 10), IP 192.168.10.45. New playbook `ansible/playbooks/truenas/elastic_vm.yml` |
| PE-3 | Install AlmaLinux 9 on Elastic VM | ❌ | Via netboot.xyz — **manual** install wizard (Kickstart does not work via netboot.xyz/iPXE EFI). Then run `vm_base.yml`. |
| PE-4 | Deploy Elastic Stack via Ansible | ❌ | `ansible/playbooks/vms/elastic.yml` — deviantony/docker-elk v9.3.0, Elasticsearch heap 8GB, Fleet Server, data volume on second disk. |
| PE-5 | NPM: expose Kibana as `kibana.cantone.net` | ❌ | HTTP/HTTPS proxy to 192.168.10.45:5601 |
| PE-6 | Deploy Elastic Agent on PVE nodes | ❌ | Fleet-managed. Integrations: system logs, metrics |
| PE-7 | Deploy Elastic Agent on TrueNAS | ❌ | Direct install (no Docker). System + ZFS metrics |
| PE-8 | Deploy Elastic Agent on k3s VMs | ❌ | After Phase 3 — Kubernetes integration |

---

## Phase 4 — Media Stack Migration

**Prerequisites:** Phase 3 stable, Phase 1 (NFS)

| # | Task | Status | Note |
|---|------|--------|-------|
| P4-1 | Radarr → k3s | ❌ | NFS for media |
| P4-2 | Sonarr → k3s | ❌ | |
| P4-3 | Lidarr → k3s | ❌ | NFS for music |
| P4-4 | Prowlarr → k3s | ❌ | |
| P4-5 | Seerr → k3s | ❌ | Overseerr fork |
| P4-6 | Tautulli → k3s | ❌ | |
| P4-7 | Wizarr → k3s | ❌ | |
| P4-8 | Audiobookshelf → k3s | ❌ | Currently running as Docker on media VM |
| P4-9 | Pinchflat → k3s (ersetzt YTdl-Material) | ❌ | YouTube Media Manager (yt-dlp basiert). YTdl-Material + MongoDB werden abgelöst. ⚠️ SQLite/Storage: Config-Dir → Longhorn (RWO), Downloads/Media → TrueNAS NFS (RWX). ⚠️ WebSockets: Traefik Ingress braucht entsprechende Middleware. **Alternative: TubeArchivist** (github.com/tubearchivist/tubearchivist) — YouTube-Archiv mit Elasticsearch-Backend + Plex-Plugin für Integration in bestehenden Plex-Stack. Mehr Features aber ressourcenintensiver (Elasticsearch). Entscheidung Pinchflat vs. TubeArchivist vor Deployment. |
| P4-10 | Finalise Plex on TrueNAS VM | ❌ | Stays there permanently, HW-transcoding |
| P4-11 | Finalise NZBGet on TrueNAS VM | ❌ | Stays there permanently |

---

## Backlog

| # | Topic | Context |
|---|-------|---------|
| B-57 | Upscayl | AI image upscaler — requires GPU. Kandidat für TrueNAS AI-VM (GTX 1060, B-42) sobald eingebaut. |
| B-56 | Dbackup | |
| B-55 | Reclaimerr | Radarr/Sonarr companion — reclaims disk space by removing watched/low-quality media. Sinnvoll nach Phase 4 (Arr-Stack auf k3s). |
| B-54 | Homelabel | Home inventory + label management. k3s. |
| B-53 | Handbrake | Video transcoding with web UI (jlesage/handbrake). k3s oder TrueNAS VM. |
| B-52 | Dedicated Jump Host (Bastion) | Dedicated VM on VLAN 1 (Management) as SSH jump host for Ansible + admin access to PVE nodes. Removes need to allow admin VLAN (192.168.20.0/24) directly on PVE nodes. After Phase 3: LXC or small VM, key-based auth only, no services. |
| B-51 | AdGuard DNS: strukturierter `dns_hosts` Datenansatz | Aktuell Forward + PTR manuell doppelt gepflegt. Refactor zu `dns_hosts` Liste in `vars/adguard.yml` — Template generiert Forward + PTR + Aliases automatisch. Neuer Host = ein Eintrag. Langfristig: Terraform schreibt Eintrag direkt bei VM-Provisioning. |
| B-50 | Host hardening baseline (Firewall + SSH + CIS) | Vor dem Aufbau weiterer VMs: einheitliche Hardening-Baseline für alle Hosts definieren. Umfasst: ufw/nftables (nur benötigte Ports), SSH hardening (`PasswordAuthentication no`, `PermitRootLogin no`), Ansible-Playbook das auf alle Host-Typen angewendet wird. Geht hand in hand mit P2-D1 (CIS Level 1 Entscheidung) — erst entscheiden, dann implementieren. |
| B-15c | AdGuard Home Sync (Pi01 → Pi02) | ✅ adguardhome-sync v0.9.0 als systemd-Service auf Pi01. Synct alle 30 Min: Filter, Rewrites, DNS-Config, Settings. DHCP + Logs/Stats deaktiviert. |
| B-49 | TrueNAS VM state monitoring | ✅ `check_vm_state()` in `truenas-monitor.sh` — alerts if any autostart VM is not RUNNING. |
| B-47 | Replace rclone Cloud Sync with Restic for versioned offsite backups | Current rclone sync = mirror only (1 copy). Restic = deduplication + retention policy. Target: `--keep-weekly 4 --prune`. Replaces current Cloud Sync task for `mediastack-config`. Interim: Hetzner Storage Box snapshots (5x Monday). |
| B-46 | Back up critical secrets in Proton Pass | `ssh/ansible`, `ssh/truenas-hetzner` private keys + `hetzner_rclone_encryption_password` + `hetzner_rclone_encryption_salt` from `secrets.yml`. Later: Sealed Secrets cluster key (P3-11). Without rclone passwords, Hetzner backups are unreadable. |
| B-2 | Test NZBGet → k3s (future) | Performance comparison TrueNAS VM vs. k3s + NFS |
| B-5 | Ansible Vault strategy | Securely manage passwords in Ansible |
| B-7 | Longhorn backup retention policy | Backup target on TrueNAS NFS configured (P3-14) — snapshot schedule + retention still to be defined |
| B-8 | DNS / Ad-Blocking | ✅ Decision: AdGuard Home on 2x Raspberry Pi 4 (→ B-15a/b/c) |
| B-9 | Terraform state remote backend | Currently local `.tfstate` |
| B-10 | AlmaLinux template update process | Update template for new AlmaLinux versions |
| B-12 | NetBox as infrastructure visualisation (CMDB, read-only) | After Phase 3 — optional. One-way sync only: IaC/infra → NetBox, never the reverse. Sources: PVE SDN integration (auto), Terraform post-apply, Ansible tasks, nmap scanner for unmanaged devices (switches, APs). Tracks: physical devices, VMs, IP prefixes per VLAN. Not for pods — use ArgoCD/Grafana/k9s for k8s workloads. |
| B-13 | CrowdSec | Collaborative IPS — possibly deploy on k3s or as LXC |
| B-14 | Renovate Bot | Automatic dependency updates for Terraform providers, Helm charts, Docker images → PRs in GitOps repos |
| B-15 | Set up AdGuard Home (2x Raspberry Pi 4) | ✅ Decision made: Pi 1 = Primary, Pi 2 = Secondary. AdGuard Home Sync between both. Both IPs in router/DHCP as DNS. Outside k3s — critical infrastructure. Unbound as recursive resolver: ❓ still open. Tasks: B-15a/b/c |
| B-15a | Pi 1: install + configure AdGuard Home | ✅ | Done 2026-04-26 — `ansible/pi/adguard.yml` |
| B-15b | Pi 2: install + configure AdGuard Home | ✅ | Done 2026-04-26 — same playbook, synced via adguardhome-sync |
| B-15c | Set up AdGuard Home Sync | ✅ | Done 2026-04-26 — adguardhome-sync v0.9.0, Pi01→Pi02, cron every 30 min |
| B-16 | Self-hosted VPN / Zero Trust | Unifi Teleport (WireGuard) covers current need. For fully self-hosted mesh VPN: evaluate Netbird (self-hosted control plane, WireGuard-based) or Headscale (self-hosted Tailscale coordination server). Tailscale rejected — external auth (KO criterion). |
| B-17 | Manage Cloudflare via Terraform | DNS records, tunnels etc. via Terraform instead of manually in dashboard |
| B-48 | Vikunja | Task + habit tracking — recurring tasks with reminders, push notifications. Android app. k3s, Postgres (Longhorn), connect Authentik. |
| B-18 | Paperless-ngx | Document management with OCR — k3s, Postgres (Longhorn). Primary document store for all non-emergency documents (invoices, contracts, statements). See storage decision below. |
| B-19 | BentoPDF | PDF toolbox (merge, split, compress, convert) |
| B-43 | FreshRSS | RSS aggregator — k3s, Postgres (Longhorn), connect Authentik, Homepage integration (widget or iframe) |
| B-20 | NPM → ingress-nginx cutover plan | Coordinated switch: DNS records, Cloudflare proxy, all services simultaneously or rolling? |
| B-23 | ~~Evaluate monitoring after Phase 3~~ | ✅ Decision: Prometheus + Grafana + Alertmanager + Node Exporter. Node Exporter baked into VM template (P2-0), stack deployed early Phase 3 (P3-8a/b/c). |
| B-25 | Mealie | Recipe server — k3s, Postgres (Longhorn), connect Authentik |
| B-26 | Frigate | NVR with object detection (cameras) — dedicated VM or k3s, requires Coral TPU or GPU for inference |
| B-27 | slskd | Soulseek client (music sharing) — k3s, NFS for downloads |
| B-28 | Falco | Runtime security for k8s — detects anomalous behaviour in containers (syscall-based). Evaluate after Phase 3. |
| B-29 | Trivy Operator | Continuous vulnerability scanning of container images directly in cluster. Evaluate after Phase 3. |
| B-30 | Kyverno | Policy engine for k8s (e.g. no container as root, image signing). Evaluate after Phase 3. |
| B-31 | Raspberry Pi (2x) — define use case | ✅ Decided: 2x Pi 4 → AdGuard Home Primary + Secondary DNS (→ B-15a/b/c) |
| B-32 | Backstage | Spotify — Service Catalog / Developer Portal. For evaluation. |
| B-45 | Set up TrueNAS alerting | 1) Configure alert service (Email or Slack). 2) Alert settings: set pool/SMART thresholds. 3) Reduce disk-monitor.sh to UDMA_CRC + Hard-Reset (ZFS/SMART alerts then redundant). |
| B-44 | ~~Configure external HDD as PBS datastore~~ | ✅ Decision made → P1-31. ZFS pool `external` with `pbs/` (NFS → PBS on PVE) + `replication/` (ZFS replication from `data` pool). Depends on P1-30 (Nextcloud data restore). |
| B-33 | Scrutiny | SMART monitoring for hard drives — web UI, InfluxDB backend. For evaluation. |
| B-34 | Kubecost | Resource usage and cost per pod/namespace in k3s cluster. For evaluation. |
| B-35 | Lens | Desktop GUI for Kubernetes. For evaluation. |
| B-36 | k9s | Terminal UI for Kubernetes. For evaluation. |
| B-37 | Cartography | Infrastructure graph tool (AWS/GCP/k8s assets as Neo4j graph). For evaluation. |
| B-38 | Inframap | Terraform state → automatically generate infrastructure diagram. For evaluation. |
| B-39 | Wazuh | SIEM + host-based IDS / security monitoring. For evaluation. |
| B-40 | OpenSCAP | Compliance scanning and security hardening (CIS benchmarks). For evaluation. |
| B-41 | Atlantis | GitOps for Terraform — automatic `plan`/`apply` on PRs. For evaluation. |
| B-42 | Install GTX 1060 6GB in truenas → AI VM | GTX 1060 6GB (ready, not yet installed) into truenas, GPU passthrough in dedicated TrueNAS AI VM. GTX 970 → Plex (P1-15), GTX 1060 6GB → AI. 6GB VRAM: 13B models with quantisation (Ollama). Zvol + VM configuration via Ansible still to be added. |
