# Network Inventory

> Current state of the physical and logical network.
> Last updated: 2026-04-05

---

## Hardware

| Device | Model | Role |
|--------|-------|------|
| Router | UniFi UCG Ultra | Router, firewall, L3 gateway |
| Switch main | UniFi US-8-60W | Main switch (rack/router room) |
| Switch secondary | UniFi USW Flex Mini | Secondary switch (next to US-8-60W) |
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
├── Port 2 ──→ Nvidia Shield       [target: VLAN 40]
├── Port 3 ──→ Hue Bridge          [target: VLAN 40]
└── Port 4 ──→ TrueNAS             [target: VLAN 10]

US-8-60W
├── Port 1 ──→ UCG Ultra (uplink)
├── Port 4 ──→ PC Julie            [target: VLAN 20]
├── Port 5 ──→ USW Flex Mini (uplink)
├── Port 7 ──→ AC Pro              [target: VLAN 1 mgmt / SSIDs tagged]
├── Port 8 ──→ PC Robin            [currently: VLAN 10 ⚠️]  [target: VLAN 20]
└── Port ? ──→ Printer (offline)   [target: VLAN 20]

USW Flex Mini
├── Port 1 ──→ US-8-60W (uplink)
├── Port 3 ──→ Helix (PVE node)   [target: Trunk — native VLAN 1, tagged 10,20,30,40]
├── Port 4 ──→ Nova  (PVE node)   [target: Trunk — native VLAN 1, tagged 10,20,30,40]
└── Port 5 ──→ Vega  (PVE node)   [target: Trunk — native VLAN 1, tagged 10,20,30,40]

AC Pro (WiFi)
├── SSID "Einhornsalat" — 2.4 + 5 GHz  [target: VLAN 20]
└── SSID "IOT"          — 2.4 GHz only  [target: VLAN 40]
```

---

## Device VLAN Placement

| Device | Connected to | Current VLAN | Target VLAN | Status |
|--------|-------------|-------------|-------------|--------|
| UCG Ultra | — | VLAN 1 | VLAN 1 | ✅ |
| US-8-60W | UCG Port 1 | VLAN 1 | VLAN 1 | ✅ |
| USW Flex Mini | US-8 Port 5 | VLAN 1 | VLAN 1 | ✅ |
| AC Pro | US-8 Port 7 | VLAN 1 | VLAN 1 (mgmt) | ✅ |
| TrueNAS | UCG Port 4 | VLAN 10 | VLAN 10 | ✅ |
| Helix (PVE mgmt) | Flex Mini Port 3 | VLAN 1 (untagged) | VLAN 1 native + Trunk | ⚠️ trunk not configured |
| Nova (PVE mgmt) | Flex Mini Port 4 | VLAN 1 (untagged) | VLAN 1 native + Trunk | ⚠️ trunk not configured |
| Vega (PVE mgmt) | Flex Mini Port 5 | VLAN 1 (untagged) | VLAN 1 native + Trunk | ⚠️ trunk not configured |
| PC Robin | US-8 Port 8 | VLAN 10 | VLAN 20 | ❌ falsches VLAN |
| PC Julie | US-8 Port 4 | unbekannt | VLAN 20 | ❓ prüfen |
| Printer | US-8 Port ? | unbekannt | VLAN 20 | ❓ offline, prüfen |
| Nvidia Shield | UCG Port 2 | unbekannt | VLAN 40 | ❓ prüfen |
| Hue Bridge | UCG Port 3 | unbekannt | VLAN 40 | ❓ prüfen |
| WiFi "Einhornsalat" | AC Pro | unbekannt | VLAN 20 | ❓ prüfen |
| WiFi "IOT" | AC Pro | unbekannt | VLAN 40 | ❓ prüfen |
| Pi 1 (DNS primary) | — | nicht angeschlossen | VLAN 1 | ⏳ Phase 1.5 |
| Pi 2 (DNS + Tailscale) | — | nicht angeschlossen | VLAN 1 | ⏳ Phase 1.5 |

---

## Required Switch Port Profiles (UniFi)

| Profile Name | Native VLAN | Tagged VLANs | Used on |
|-------------|------------|--------------|---------|
| Management | VLAN 1 | — | Spare ports |
| Client | VLAN 20 | — | PC Julie, PC Robin, Printer |
| Untrust | VLAN 40 | — | Hue Bridge (if moved to switch) |
| Server | VLAN 10 | — | TrueNAS (if moved to switch) |
| PVE-Trunk | VLAN 1 | 10, 20, 30, 40 | Helix, Nova, Vega |
| Uplink-Trunk | VLAN 1 | 10, 20, 30, 40 | US-8 Port 5 ↔ Flex Mini Port 1 |

> UCG Ultra ports with single-device access (Shield, Hue Bridge, TrueNAS) are configured
> as Access ports directly on the router — no trunk needed.

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

| # | Issue | Impact |
|---|-------|--------|
| 1 | PC Robin im falschen VLAN (VLAN 10 / Server) | Robin hat ungewollten Zugriff auf Server-Netz |
| 2 | PVE nodes ohne explizites VLAN-Tag auf mgmt-Interface | Implicit VLAN 1 funktioniert, aber unkontrolliert |
| 3 | Trunk-Ports auf Flex Mini nicht konfiguriert | VMs können keine VLAN-Tags gegenüber Switch nutzen |
| 4 | Keine Inter-VLAN Firewall-Regeln | Alle VLANs können sich gegenseitig erreichen |
| 5 | SSID → VLAN Mapping nicht verifiziert | Einhornsalat / IOT VLAN-Tags unbestätigt |

---

## Doc Note

`docs/current.md` und `docs/network-firewall.md` referenzieren "VLAN 2" als Management VLAN —
korrekt ist **VLAN 1** (192.168.1.0/24), das native UniFi-Netzwerk. Docs werden in Folgeschritten angepasst.
