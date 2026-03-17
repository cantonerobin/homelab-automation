# Homelab — Roadmap

> Phasen und Tasks um vom Ist-Zustand (`current.md`) zum Ziel-Zustand (`target.md`) zu kommen.
> Letzte Aktualisierung: 2026-03-17

---

## Legende
- ✅ Erledigt
- 🔄 In Arbeit
- ⚠️ Blockiert / Problem offen
- ❌ Ausstehend
- ❓ Entscheidung ausstehend

---

## Phase 0 — Vorbereitung

| # | Task | Status | Notiz |
|---|------|--------|-------|
| P0-1 | SSH-Private-Key aus Git-History entfernen (`git filter-repo`) | ✅ | Erledigt |
| P0-2 | Neues SSH-Keypair für Ansible generieren | ✅ | Erledigt |
| P0-3 | `cipassword = "test123"` aus `vm_k3s.tf` entfernen | ✅ | Erledigt |
| P0-5 | netboot.xyz VM deployen (`terraform apply`) | ✅ | Deployed auf einem der kleinen Nodes |
| P0-6 | Unifi DHCP Option 66/67 für netboot.xyz konfigurieren | ✅ | Erledigt — DHCP gibt TFTP-Server + Dateiname an PXE-Clients |
| P0-7 | Statische IPs für k3s VMs via Cloud-Init | ✅ | VLAN 10: .10/.11/.12, GW .1 |
| P0-8 | Ansible Inventory befüllen (IPs für k3s-nova/helix/vega) | ✅ | PVE-Nodes + k3s VMs eingetragen |
| P0-9 | LXC-Konfigurationen exportieren → `docs/current.md` | ✅ | Docker-Composes in `docs/legacy/docker-compose/` ✅ — IPs + Ports dokumentiert |
| P0-10 | Netzwerk-Schema dokumentieren | ✅ | In `docs/current.md` (Ist) + `docs/target.md` (Ziel) integriert |
| P0-11 | Service-Inventar (Ports, DNS, Abhängigkeiten) | ❌ | Vor Phase 1 empfohlen |
| P0-12 | `k3s-manifests` Git-Repo erstellen | ❌ | Für Phase 3 GitOps |
| P0-13 | Ansible-Ordnerstruktur im Repo anlegen | ✅ | `proxmox/`, `truenas/`, `k3s/` |
| P0-14 | Ansible Playbooks aus anderem Git-Repo in `homelab-automation` migrieren | 🔄 | `ansible/proxmox/security-updates.yml` migriert — altes Repo bleibt aktiv via CLI bis Git-basierte Automation läuft, danach archivieren |
| P0-15 | SSH Keypair in `ssh/` (Repo-Root) zentralisieren | ✅ | `ssh/ansible.pub` (committed), `ssh/ansible` (gitignored). Terraform + Ansible referenzieren denselben Key. `ansible/ansible.cfg` mit `private_key_file` angelegt |

---

## Phase 1 — TrueNAS Migration

**Voraussetzungen:** P0-9 (LXC Docs)

| # | Task | Status | Notiz |
|---|------|--------|-------|
| P1-0 | Mediastack VM: Configs + Daten sichern für Migration auf TrueNAS | ❌ | Plex, NZBGet, Radarr/Sonarr/etc. Configs sichern — VM wird auf TrueNAS neu aufgebaut (P1-14). ⚠️ Minimale Downtime anstreben — externe User! |
| P1-1 | Ceph OSDs von orion evakuieren (`ceph osd out`) | ❌ | Stunden-Prozess, sorgfältig planen |
| P1-2 | Ceph Rebalancing abwarten (HEALTH_OK) | ❌ | Abhängig P1-1 |
| P1-3 | orion aus PVE-Cluster entfernen (`pvecm delnode`) | ❌ | Abhängig P1-2 |
| P1-4 | Synology Daten → externe HDD sichern (`rsync`) | ✅ | 3.4TB gesichert, Größe + rsync dry-run verifiziert |
| P1-5 | TrueNAS Scale auf orion installieren (2x 250GB SSD Mirror) | ✅ | Läuft auf 192.168.10.25 |
| P1-6 | Synology Disks ausbauen → in TrueNAS einbauen | ✅ | 4x 3TB + 1x 6TB eingebaut |
| P1-7 | ZFS Pool `data` erstellen: 4x 3TB RAIDZ1 | ✅ | Via Ansible Playbook |
| P1-8 | ZFS Pool `archive` erstellen: 1x 6TB | ✅ | Via Ansible Playbook |
| P1-9 | L2ARC: 1x 1TB SSD hinzufügen | ❌ | Optional, für Performance |
| P1-10 | Datasets anlegen: `media`, `downloads`, `backups`, `backups/longhorn`, `nextcloud` | ✅ | Via Ansible Playbook |
| P1-11 | Daten restoren: externe HDD → TrueNAS `data` Pool | ❌ | Noch ausstehend |
| P1-12 | NFS-Shares konfigurieren | ✅ | Via Ansible Playbook — `media-data`, `downloads`, `nextcloud`, `backups` |
| P1-14 | TrueNAS VM: Mediastack VM einrichten (4 cores, 16GB, 50GB) | ✅ | VM angelegt via Ansible — OS-Install via PXE ausstehend (P1-28) |
| P1-15 | GPU-Passthrough in TrueNAS konfigurieren (Mediastack VM) | ⚠️ | GTX 970 (installiert) → Passthrough an Mediastack VM. Ryzen 7 3700X hat kein iGPU — TrueNAS verweigert Passthrough der einzigen GPU ("At least 1 GPU required by host"). Optionen: (A) Zweite GPU einbauen (GT 710 ~20€) als Host-Display → GTX 970 frei. (B) vfio-pci.ids manuell per TrueNAS Sysctl setzen → headless, kein physischer Konsolenzugang mehr. Vorerst zurückgestellt. |
| P1-16 | Plex in Mediastack VM installieren | ❌ | NFS auf media/downloads mounten, GPU für HW-Transcoding (`/dev/dri`) |
| P1-17 | NZBGet in Mediastack VM installieren | ❌ | Download + Entpacken lokal auf Config-Disk (`/opt/mediastack/nzbget/tmp`) — erst nach Abschluss auf NFS (`/mnt/downloads`) verschieben. Vermeidet NFS-Last bei intensivem I/O. |
| P1-19 | TrueNAS Test-VM auf PVE erstellen (TrueNAS Scale ISO, virtuelle Disks) | ✅ | Test-VM läuft (ID 2018, IP 192.168.10.73) — Disks mit serials via `qm set` konfiguriert |
| P1-20 | Ansible Playbook: TrueNAS Konfiguration entwickeln + gegen Test-VM validieren | ✅ | `ansible/truenas/configure.yml` — Pools, Datasets, NFS, Snapshot-Tasks, Scrub-Tasks. Vollständig via REST API (`uri`), serial-basierte Disk-Erkennung. Gegen Test-VM erfolgreich validiert. |
| P1-21 | Ansible Playbook auf echte TrueNAS Hardware anwenden | ✅ | Erfolgreich auf 192.168.10.25. Pools, Datasets, Zvols, NFS, Snapshots, Scrubs, VMs, Netzwerk konfiguriert. |
| P1-22 | Ansible Playbook: TrueNAS API Endpoints validieren | ✅ | Implizit durch P1-21 — midclt-basiert, alle Endpoints funktional. Integer-Typing-Fixes für volsize + vm-ID notwendig gewesen. |
| P1-23 | Ansible Playbook: Netzwerk konfigurieren | ✅ | Hostname, statische IP, Gateway, DNS via `midclt call network.configuration.update` + `interface.update`. IP in `vars/config.yml` anpassen vor Ausführung. |
| P1-24 | Ansible Playbook: TLS-Zertifikat via Step-CA deployen | ❌ | Step-CLI auf Control-Node: cert ausstellen → via `POST /api/v2.0/certificate/` importieren → als UI-Cert setzen |
| P1-25 | Ansible Playbook: Step-CA Root-Cert → TrueNAS Truststore | ❌ | Root-Cert nach `/usr/local/share/ca-certificates/homelab-ca.crt` + `update-ca-certificates`. Abhängig P1-24 |
| P1-26 | Ansible Playbook: Alert-Service konfigurieren | ❌ | Email-Alerts via `POST /api/v2.0/alertservice` (typ: Mail + SMTP-Credentials) |
| P1-27 | Dataset-Konfiguration dokumentieren | ❌ | Recordsize + Compression pro Dataset: `media` (1M, LZ4), `downloads` (128k, LZ4), `nextcloud` (16k, LZ4), `backups` (128k, ZSTD) |
| P1-28 | Mediastack VM via netboot.xyz installieren | ✅ | OS installiert, vm_base Playbook ausgeführt |
| P1-29 | TrueNAS Cloud Sync einrichten: Rclone → Hetzner Storage Box | ❌ | Inkrementell, verschlüsselt — `data` Pool inkl. Longhorn-Backup-Dataset. Abhängig P1-10 |

---

## Phase 2 — PVE Cluster Rebuild (Rolling)

**Voraussetzungen:** P0-5 (netboot.xyz erreichbar)
**Hinweis:** Ceph wird entfernt. 1TB NVMe (ehem. Ceph OSD) pro Node → local-lvm Datastore für VM-Storage.

*Für jeden der 3 Nodes (nova → helix → vega) wiederholen:*

| # | Task | Status | Notiz |
|---|------|--------|-------|
| P2-1 | Ansible Playbook: PVE-Node Konfiguration schreiben | ❌ | `ansible/proxmox/` |
| P2-2 | [nova] Backup aller VMs/LXCs auf nova sicherstellen | ❌ | Vor jeder Aktion — TrueNAS Snapshots + Config-Backups prüfen |
| P2-3 | [nova] VMs/LXCs auf helix/vega migrieren | ❌ | |
| P2-4 | [nova] Ceph OSD entfernen + Rebalancing abwarten | ❌ | |
| P2-5 | [nova] Node aus Cluster entfernen | ❌ | |
| P2-6 | [nova] PVE via netboot.xyz neu installieren | ❌ | |
| P2-7 | [nova] Node zurück in Cluster (`pvecm add`) | ❌ | |
| P2-8 | [nova] 1TB NVMe als local-lvm Datastore konfigurieren | ❌ | Ersetzt Ceph OSD — PVE Datacenter → Storage → local-lvm |
| P2-9 | [nova] Ansible: PVE-Node konfigurieren | ❌ | |
| P2-10 | [helix] — gleiche Schritte wie nova (P2-2 bis P2-9) | ❌ | |
| P2-11 | [vega] — gleiche Schritte wie nova (P2-2 bis P2-9) | ❌ | |
| P2-12 | k3s VMs von `ceph_data` auf local-lvm migrieren | ❌ | ⚠️ Vor P2-13 zwingend! VMs via PVE Storage-Migration (qm move-disk) auf local-lvm des jeweiligen Nodes. Terraform-Storage-Variable danach auf `local-lvm` umstellen. |
| P2-13 | Ceph komplett deinstallieren (`pveceph purge` auf letztem Node) | ❌ | Erst nach P2-12 — dann kein `ceph_data` mehr vorhanden |

---

## Phase POC — Proof of Concept

**Zeitpunkt:** Parallel zu / direkt nach Phase 3 Bootstrap (P3-4/P3-5)

> PoCs brauchen einen laufenden k3s Cluster — daher de facto frühe Phase 3.
> POC-1 ist Ausnahme: vor Phase 2.

| # | Task | Status | Go/No-Go Kriterium |
|---|------|--------|-------------------|
| POC-1 | netboot.xyz: PVE Installer über Netzwerk booten testen | ❌ | Vor Phase 2 — PVE-Installer erscheint, Netzwerk-Boot stabil |
| POC-3 | NFS Subdir Provisioner: PVC erstellen/löschen, Pod-Restart testen | ❌ | Vor P3-12 — braucht k3s-Cluster (nach P3-5). Keine Datenverluste, Mount stabil |
| POC-4 | Longhorn: deployen, Backup Target auf TrueNAS NFS konfigurieren, Failover testen | ❌ | Vor P3-13 — braucht k3s-Cluster (nach P3-5). Entscheidung (Hybrid) getroffen, PoC validiert Implementation |
| POC-5 | Nextcloud PoC: Helm Chart + Postgres (Longhorn) + Datenstorage TrueNAS NFS | ❌ | Abhängig POC-3+POC-4 + P1-12. Go: Migration P3-23. No-Go: AIO bleibt auf TrueNAS VM |

---

## Phase 3 — k3s Cluster

**Voraussetzungen:** Phase 1 abgeschlossen (NFS via P1-12)

| # | Task | Status | Notiz |
|---|------|--------|-------|
| P3-1 | Netzwerk-Problem in k3s VMs klären (`ip addr`) | ✅ | Gelöst durch Terraform Provider Update — Bug im Provider in Kombination mit `user`-Config |
| P3-2 | Statische IPs in VMs verifizieren | ✅ | Abhängig P3-1 |
| P3-2a | Terraform: k3s VMs — zweite virtio-Disk (100GB) für Longhorn provisionieren | ❌ | Separate Disk auf `/var/lib/longhorn` — IO-Trennung OS/Replikation. Root-Disk: 40GB, Longhorn-Disk: 100GB → ~33GB nutzbarer Longhorn-Space (3x Replikation) |
| P3-3 | Ansible Playbook: zweite Disk formatieren + auf `/var/lib/longhorn` mounten | ❌ | Vor k3s-Install ausführen — Longhorn erkennt das Verzeichnis automatisch |
| P3-4 | Ansible Playbook: k3s Server auf k3s-nova installieren (`--cluster-init`) | ❌ | `ansible/k3s/` — erster Node, initialisiert embedded etcd |
| P3-5 | Ansible Playbook: k3s Server auf k3s-helix + k3s-vega installieren (`--server`) | ❌ | Alle 3 Nodes sind Server — HA Control Plane |
| P3-6 | Kubeconfig lokal verfügbar machen | ❌ | |
| P3-7 | `k3s-manifests` Repo strukturieren (bootstrap, apps/) | ❌ | Abhängig P0-12 |
| P3-8 | ArgoCD deployen und konfigurieren | ❌ | App-of-Apps Pattern |
| P3-9 | ingress-nginx deployen (via ArgoCD) | ❌ | |
| P3-10 | cert-manager deployen + Step-CA Integration | ❌ | cert-manager via ACME gegen bestehenden Step-CA LXC — Step-CA bleibt vorerst als LXC |
| P3-11 | Sealed Secrets deployen | ❌ | ⚠️ Cluster-Key nach Deploy sichern (TrueNAS) — ohne Key können bei Cluster-Rebuild keine SealedSecrets entschlüsselt werden |
| P3-12 | NFS Subdir Provisioner deployen | ❌ | Abhängig Phase 1 P1-12 |
| P3-13 | Longhorn deployen (via ArgoCD) | ❌ | Für: DBs, stateful Apps (RWO, repliziert über 3 Nodes) |
| P3-14 | Longhorn Backup Target → TrueNAS NFS konfigurieren | ❌ | Abhängig P3-13 + P1-12. Longhorn-Backups werden via TrueNAS Cloud Sync (P1-28) zu Hetzner mitgenommen |
| P3-15 | Authentik deployen (SSO) | ❌ | Früh deployen. Anbinden: Nextcloud, Firefly III, Homepage, Uptime Kuma, Arr-Services, Grafana (wenn Monitoring kommt). NICHT anbinden: Proxmox, TrueNAS, ArgoCD, Longhorn UI (Infra-Tools, nur via VPN) |
| P3-16 | Cloudflare DynDNS → k3s | ❌ | Prio: Hoch |
| P3-17 | Homepage → k3s | ❌ | Prio: Hoch |
| P3-18 | Uptime Kuma → k3s | ❌ | Prio: Hoch |
| P3-19 | Gotify → k3s | ❌ | Prio: Mittel |
| P3-20 | Nginx Reverse Proxy ablösen (durch ingress-nginx) | ❌ | ⚠️ Cutover-Plan noch zu definieren — koordinierter Wechsel aller DNS/Cloudflare-Einträge nötig |
| P3-21 | Step-CA → k3s (PKI-Migration!) | ❌ | Prio: Mittel, kritischer State |
| P3-22 | Nextcloud AIO auf TrueNAS VM einrichten (Übergangslösung) | ❌ | AIO Container auf TrueNAS VM — wie bisher, bis PoC (POC-5) validiert ist |
| P3-23 | Nextcloud → k3s migrieren (nach validiertem PoC-5) | ❌ | Helm Chart + Postgres (Longhorn) + NFS-Dataset (bleibt bestehen). Abhängig POC-5 erfolgreich |
| P3-24 | Firefly III deployen | ❌ | |
| P3-25 | HomeAssistant VM (PVE) mit USB-Passthrough einrichten | ❌ | Zigbee-Stick, kein k3s — Dev-VM läuft bereits (10.61), Prod-Setup mit USB-Passthrough ausstehend |
| P3-26 | GitLab self-hosted deployen | ❌ | Erst wenn Phase 3 stabil |
| P3-27 | GitLab Push Mirror einrichten: self-hosted → GitLab.com | ❌ | Automatisches Offsite-Backup aller Repos bei jedem Commit. Übergangsphase: GitHub bis GitLab self-hosted läuft |

---

## Phase 4 — Media Stack Migration

**Voraussetzungen:** Phase 3 stabil, Phase 1 (NFS)

| # | Task | Status | Notiz |
|---|------|--------|-------|
| P4-1 | Radarr → k3s | ❌ | NFS für Media |
| P4-2 | Sonarr → k3s | ❌ | |
| P4-3 | Lidarr → k3s | ❌ | NFS für Musik |
| P4-4 | Prowlarr → k3s | ❌ | |
| P4-5 | Seerr → k3s | ❌ | Overseerr-Fork |
| P4-6 | Tautulli → k3s | ❌ | |
| P4-7 | Wizarr → k3s | ❌ | |
| P4-8 | Audiobookshelf → k3s | ❌ | Läuft aktuell als Docker auf Media-VM |
| P4-9 | YTdl-Material → k3s | ❌ | MongoDB migrieren, mongo 4.4 ist EOL — upgrade prüfen |
| P4-10 | Plex auf TrueNAS VM final einrichten | ❌ | Bleibt dauerhaft dort, HW-Transcoding |
| P4-11 | NZBGet auf TrueNAS VM final einrichten | ❌ | Bleibt dauerhaft dort |

---

## Backlog

| # | Thema | Kontext |
|---|-------|---------|
| B-2 | NZBGet → k3s testen (Zukunft) | Performance-Vergleich TrueNAS VM vs. k3s + NFS |
| B-5 | Ansible Vault Strategie | Passwörter in Ansible sicher verwalten |
| B-7 | Longhorn Backup Retention Policy | Backup Target auf TrueNAS NFS konfiguriert (P3-14) — Snapshot-Schedule + Retention noch zu definieren |
| B-8 | DNS / Ad-Blocking | Pi-hole oder AdGuard Home? |
| B-9 | Terraform State Remote Backend | Aktuell lokale `.tfstate` |
| B-10 | AlmaLinux Template Update-Prozess | Template bei neuen AlmaLinux-Versionen aktualisieren |
| B-12 | Netbox als Visualisierungstool | Nach Phase 3 — optional, nie als Terraform/Ansible Dependency |
| B-13 | CrowdSec | Collaborative IPS — evtl. auf k3s oder als LXC deployen |
| B-14 | Renovate Bot | Automatische Dependency-Updates für Terraform Provider, Helm Charts, Docker Images → PRs in GitOps-Repos |
| B-15 | AdGuard Home einrichten (2x Raspberry Pi 4) | ✅ Entscheidung getroffen: Pi 1 = Primary, Pi 2 = Secondary. AdGuard Home Sync zwischen beiden. Beide IPs im Router/DHCP als DNS. Außerhalb k3s — kritische Infrastruktur. Unbound als rekursiver Resolver: ❓ noch offen. Tasks: B-15a/b/c |
| B-15a | Pi 1: AdGuard Home installieren + konfigurieren | ❌ Filterlisten, DNS-over-HTTPS/TLS, lokale DNS-Einträge |
| B-15b | Pi 2: AdGuard Home installieren + konfigurieren | ❌ Gleiche Basis-Config wie Pi 1 |
| B-15c | AdGuard Home Sync einrichten | ❌ Filterlisten + Einstellungen automatisch von Pi 1 → Pi 2 synchronisieren |
| B-16 | Tailscale | Zero-Config VPN für Remote-Zugriff. Pi 2 (AdGuard Secondary) als Subnet Router: `tailscale up --advertise-routes=192.168.10.0/24,192.168.1.0/24`. Kein Port-Forwarding nötig. Ansible Playbook schreiben. |
| B-17 | Cloudflare via Terraform verwalten | DNS-Records, Tunnel etc. per Terraform statt manuell im Dashboard |
| B-18 | Paperless-ngx | Dokumentenverwaltung mit OCR |
| B-19 | BentoPDF | PDF-Toolbox (merge, split, compress, convert) |
| B-20 | NPM → ingress-nginx Cutover-Plan | Koordinierter Wechsel: DNS-Records, Cloudflare-Proxy, alle Services gleichzeitig oder rolling? |
| B-23 | Monitoring nach Phase 3 evaluieren | Elastic Stack gestrichen (zu ressourcenintensiv für Hardware). Kandidat: Grafana + Prometheus. Entscheidung nach Phase 3 |
| B-25 | Mealie | Rezept-Server — k3s, Postgres (Longhorn), Authentik anbinden |
| B-26 | Frigate | NVR mit Objekterkennung (Kameras) — dedizierte VM oder k3s, benötigt Coral TPU oder GPU für Inferenz |
| B-27 | slskd | Soulseek-Client (Musik-Sharing) — k3s, NFS für Downloads |
| B-28 | Falco | Runtime Security für k8s — erkennt anomales Verhalten in Containern (syscall-basiert). Nach Phase 3 evaluieren. |
| B-29 | Trivy Operator | Continuous Vulnerability Scanning der Container-Images direkt im Cluster. Nach Phase 3 evaluieren. |
| B-30 | Kyverno | Policy Engine für k8s (z.B. kein Container als root, Image-Signing). Nach Phase 3 evaluieren. |
| B-31 | Raspberry Pi (2x) — Verwendungszweck definieren | ✅ Entschieden: 2x Pi 4 → AdGuard Home Primary + Secondary DNS (→ B-15a/b/c) |
| B-32 | Backstage | Spotify — Service Catalog / Developer Portal. Zum Anschauen. |
| B-33 | Scrutiny | SMART-Monitoring für Festplatten — Web-UI, InfluxDB-Backend. Zum Anschauen. |
| B-34 | Kubecost | Ressourcenverbrauch und Kosten pro Pod/Namespace im k3s Cluster. Zum Anschauen. |
| B-35 | Lens | Desktop-GUI für Kubernetes. Zum Anschauen. |
| B-36 | k9s | Terminal-UI für Kubernetes. Zum Anschauen. |
| B-37 | Cartography | Infrastruktur-Graph-Tool (AWS/GCP/k8s Assets als Neo4j-Graph). Zum Anschauen. |
| B-38 | Inframap | Terraform-State → Infrastruktur-Diagramm automatisch generieren. Zum Anschauen. |
| B-39 | Wazuh | SIEM + Host-based IDS / Security Monitoring. Zum Anschauen. |
| B-40 | OpenSCAP | Compliance-Scanning und Security-Hardening (CIS Benchmarks). Zum Anschauen. |
| B-41 | Atlantis | GitOps für Terraform — automatischer `plan`/`apply` auf PRs. Zum Anschauen. |
| B-42 | GTX 1060 6GB in orion einbauen → AI-VM | GTX 1060 6GB (liegt bereit) in orion einbauen, GPU-Passthrough in dedizierte TrueNAS AI-VM. GTX 970 → Plex (P1-15), GTX 1060 6GB → AI. 6GB VRAM: 13B-Modelle mit Quantisierung (Ollama). Zvol + VM-Konfiguration via Ansible noch zu ergänzen. |
