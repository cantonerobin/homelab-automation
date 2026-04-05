# Network Inventory

> Current state of the physical and logical network.
> Last updated: 2026-04-05

---

## Hardware

| Device | Model | Role |
|--------|-------|------|
| Router | UniFi UCG Ultra | Router, firewall, L3 gateway |
| Switch main | UniFi US-8-60W | Main switch (rack/router room) — PoE on ports 5–8 |
| ~~Switch secondary~~ | ~~UniFi USW Flex Mini~~ | Ausgebaut — unzureichende VLAN-Unterstützung (kein native VLAN ≠ 1 mit tagged Traffic) |
| AP | UniFi AC Pro | WiFi access point |

> **USW Flex Mini — VLAN note:** Full VLAN tagging and trunk ports supported.
> The UniFi UI warning refers to missing L3 features (no routing, no IGMP snooping) — not relevant here.

---

## VLAN / Network Segments

| VLAN ID | Subnet | Name | Purpose |
|---------|--------|------|---------|
| 1 | 192.168.1.0/24 | Management | UCG Ultra, switches, APs, PVE nodes (mgmt), Raspberry Pis (after P1.5) |
| 10 | 192.168.10.0/24 | Server | PVE VMs/LXCs, TrueNAS, k3s cluster |
| 20 | 192.168.20.0/24 | Client | PCs, printer, WiFi SSID "Einhornsalat" |
| 30 | 192.168.30.0/24 | DMZ | Externally exposed services (future) |
| 40 | 192.168.40.0/24 | Untrust | IoT, WiFi SSID "IOT", Nvidia Shield, Hue Bridge |

> VLAN 1 is the UniFi native/default network. All 5 networks are configured with separate L2/L3 segments.
> Firewall rules between VLANs: **not yet configured** — see `docs/network-firewall.md`.

---

## Physical Topology

```
UCG Ultra
├── Port 1 ──→ US-8-60W (uplink)
├── Port 2 ──→ Nvidia Shield       [VLAN 40]
├── Port 3 ──→ Hue Bridge          [VLAN 40]
└── Port 4 ──→ TrueNAS             [VLAN 10]

US-8-60W (PoE auf Ports 5–8)
├── Port 1 ──→ UCG Ultra (uplink)  [Default/Trunk]
├── Port 2 ──→ Helix (PVE node)   [PVE-Trunk: native VLAN 10, tagged 1/20/30/40]
├── Port 3 ──→ Nova  (PVE node)   [PVE-Trunk: native VLAN 10, tagged 1/20/30/40]
├── Port 4 ──→ Vega  (PVE node)   [PVE-Trunk: native VLAN 10, tagged 1/20/30/40]
├── Port 5 ──→ (leer / Reserve)
├── Port 6 ──→ PC Julie            [Client: VLAN 20]
├── Port 7 ──→ AC Pro              [Default/Trunk]
└── Port 8 ──→ PC Robin            [Client: VLAN 20]

AC Pro (WiFi)
├── SSID "Einhornsalat" — 2.4 + 5 GHz  [VLAN 20]
└── SSID "IOT"          — 2.4 GHz only  [VLAN 40]
```

---

## Device VLAN Placement

| Device | Connected to | VLAN | Status |
|--------|-------------|------|--------|
| UCG Ultra | — | VLAN 1 | ✅ |
| US-8-60W | UCG Port 1 | VLAN 1 | ✅ |
| USW Flex Mini | US-8 Port 5 | VLAN 1 | ✅ |
| AC Pro | US-8 Port 7 | VLAN 1 (mgmt) | ✅ |
| TrueNAS | UCG Port 4 | VLAN 10 | ✅ |
| Helix (PVE mgmt) | US-8-60W Port 2 | VLAN 10 + Trunk | ✅ |
| Nova (PVE mgmt) | US-8-60W Port 3 | VLAN 10 + Trunk | ✅ |
| Vega (PVE mgmt) | US-8-60W Port 4 | VLAN 10 + Trunk | ✅ |
| PC Robin | US-8 Port 8 | VLAN 20 | ✅ |
| PC Julie | US-8 Port 4 | VLAN 20 | ✅ |
| Printer | US-8 Port ? | VLAN 20 | ✅ |
| Nvidia Shield | UCG Port 2 | VLAN 40 | ✅ |
| Hue Bridge | UCG Port 3 | VLAN 40 | ✅ |
| WiFi "Einhornsalat" | AC Pro | VLAN 20 | ✅ |
| WiFi "IOT" | AC Pro | VLAN 40 | ✅ |
| Pi 1 (DNS primary) | — | — | ⏳ Phase 1.5 |
| Pi 2 (DNS + Tailscale) | — | — | ⏳ Phase 1.5 |

---

## Current Switch Port Configuration

### UCG Ultra
| Port | Profile | Device | Correct? |
|------|---------|--------|----------|
| 1 | Default | US-8-60W (uplink) | ✅ |
| 2 | IOT (VLAN 40) | Nvidia Shield | ✅ |
| 3 | IOT (VLAN 40) | Hue Bridge | ✅ |
| 4 | Server (VLAN 10) | TrueNAS | ✅ |

### US-8-60W
| Port | Profile | Device | Status |
|------|---------|--------|--------|
| 1 | Default (Trunk) | UCG Ultra (uplink) | ✅ |
| 2 | PVE-Trunk (native VLAN 10, tagged 1/20/30/40) | Helix | ✅ |
| 3 | PVE-Trunk (native VLAN 10, tagged 1/20/30/40) | Nova | ✅ |
| 4 | PVE-Trunk (native VLAN 10, tagged 1/20/30/40) | Vega | ✅ |
| 5 | — | leer (Reserve) | — |
| 6 | Client (VLAN 20) | PC Julie | ✅ |
| 7 | Default (Trunk) | AC Pro | ✅ |
| 8 | Client (VLAN 20) | PC Robin | ✅ |

### USW Flex Mini
Ausgebaut. Begründung: unterstützt kein native VLAN ≠ 1 in Kombination mit tagged VLANs (Hardware-Einschränkung).

---

## Required Port Profile Changes (UniFi)

| Profile Name | Native VLAN | Tagged VLANs | Used on |
|-------------|------------|--------------|---------|
| Client | VLAN 20 | — | PC Julie (US-8 P4), PC Robin (US-8 P8), Printer |
| PVE-Trunk | VLAN 10 | 1, 20, 30, 40 | Helix, Nova, Vega (Flex Mini P3/4/5) |
| Uplink-Trunk | VLAN 1 | 10, 20, 30, 40 | US-8 Port 5 + Flex Mini Port 1 |
| AP-Trunk | VLAN 1 | 20, 40 | AC Pro (US-8 P7) |

> **PVE-Trunk native VLAN 10:** PVE management bleibt auf 192.168.10.x erreichbar (kein Lockout-Risiko).
> Migration PVE mgmt → VLAN 1 (192.168.1.x) erst nach Tailscale — siehe Phase C im Umsetzungsplan.

> UCG Ultra Ports 2/3/4 (Shield, Hue Bridge, TrueNAS) sind bereits korrekt konfiguriert.

---

## PVE VLAN Configuration

- `vmbr0` VLAN-aware: ✅ bereits aktiv auf allen Nodes
- PVE management interface VLAN: ⚠️ aktuell untagged (läuft implizit auf VLAN 1)
- VM/LXC VLAN tags: teilweise gesetzt — IPs siehe `docs/current.md`

Target nach Phase 1.5 (P1.5-8 / P1.5-9):
- PVE mgmt interface: explizit VLAN 1 (192.168.1.x — neue statische IPs)
- Alle VMs/LXCs: VLAN tag 10 (Server), außer explizit anders platziert
- Trunk-Ports auf Flex Mini: native VLAN 1 + tagged 10, 20, 30, 40

---

## Open Issues

| # | Issue | Impact | Wann |
|---|-------|--------|------|
| 1 | Keine Inter-VLAN Firewall-Regeln | Alle VLANs können sich gegenseitig erreichen | Nach Tailscale (Phase B) |
| 2 | PVE mgmt-Interface noch auf VLAN 10 (192.168.10.x) | PVE-Nodes nicht im Management-VLAN | Nach Tailscale (Phase C) |
| 3 | PVE VM/LXC VLAN-Tags noch nicht vollständig gesetzt | VMs teilweise im falschen VLAN | Phase A4 |

---

## Doc Note

`docs/current.md` und `docs/network-firewall.md` referenzieren "VLAN 2" als Management VLAN —
korrekt ist **VLAN 1** (192.168.1.0/24), das native UniFi-Netzwerk. Docs werden in Folgeschritten angepasst.
