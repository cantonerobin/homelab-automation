# Network Inventory

> Current state of the physical and logical network.
> Last updated: 2026-04-05

---

## Hardware

| Device | Model | Role |
|--------|-------|------|
| Router | UniFi UCG Ultra | Router, firewall, L3 gateway |
| Switch main | UniFi US-8-60W | Main switch (rack/router room) — PoE on ports 5–8 |
| ~~Switch secondary~~ | ~~UniFi USW Flex Mini~~ | Removed — hardware limitation: no native VLAN ≠ 1 with tagged traffic |
| AP | UniFi AC Pro | WiFi access point |

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

US-8-60W (PoE on ports 5–8)
├── Port 1 ──→ UCG Ultra (uplink)  [Default/Trunk]
├── Port 2 ──→ Helix (PVE node)   [PVE-Trunk: native VLAN 10, tagged 1/20/30/40]
├── Port 3 ──→ Nova  (PVE node)   [PVE-Trunk: native VLAN 10, tagged 1/20/30/40]
├── Port 4 ──→ Vega  (PVE node)   [PVE-Trunk: native VLAN 10, tagged 1/20/30/40]
├── Port 5 ──→ (empty / spare)
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
| AC Pro | US-8 Port 7 | VLAN 1 (mgmt) | ✅ |
| TrueNAS | UCG Port 4 | VLAN 10 | ✅ |
| Helix (PVE mgmt) | US-8-60W Port 2 | VLAN 10 + Trunk | ✅ |
| Nova (PVE mgmt) | US-8-60W Port 3 | VLAN 10 + Trunk | ✅ |
| Vega (PVE mgmt) | US-8-60W Port 4 | VLAN 10 + Trunk | ✅ |
| PC Robin | US-8 Port 8 | VLAN 20 | ✅ |
| PC Julie | US-8 Port 6 | VLAN 20 | ✅ |
| Printer | US-8 Port ? | VLAN 20 | ✅ |
| Nvidia Shield | UCG Port 2 | VLAN 40 | ✅ |
| Hue Bridge | UCG Port 3 | VLAN 40 | ✅ |
| WiFi "Einhornsalat" | AC Pro | VLAN 20 | ✅ |
| WiFi "IOT" | AC Pro | VLAN 40 | ✅ |
| Pi 1 (DNS primary) | — | — | ⏳ Phase 1.5 |
| Pi 2 (DNS + Tailscale) | — | — | ⏳ Phase 1.5 |

---

## Switch Port Configuration

### UCG Ultra
| Port | Profile | Device | Status |
|------|---------|--------|--------|
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
| 5 | — | empty (spare) | — |
| 6 | Client (VLAN 20) | PC Julie | ✅ |
| 7 | Default (Trunk) | AC Pro | ✅ |
| 8 | Client (VLAN 20) | PC Robin | ✅ |

### USW Flex Mini
Removed. Hardware limitation: does not support native VLAN ≠ 1 in combination with tagged VLANs.

---

## PVE VLAN Configuration

- `vmbr0` VLAN-aware: ✅ enabled on all nodes
- PVE management interface: ⚠️ currently on VLAN 10 (192.168.10.x) — interim state
- VM/LXC VLAN tags: partially set — see `docs/current.md` for IPs

Target after Phase 1.5 (P1.5-8 / P1.5-9):
- PVE mgmt interface: VLAN 1 (192.168.1.x — new static IPs)
- All VMs/LXCs: VLAN tag 10 (Server), unless explicitly placed elsewhere

---

## Open Issues

| # | Issue | Impact | When |
|---|-------|--------|------|
| 1 | No inter-VLAN firewall rules | All VLANs can reach each other | After Tailscale (Phase B) |
| 2 | PVE mgmt interface still on VLAN 10 (192.168.10.x) | PVE nodes not in Management VLAN | After Tailscale (Phase C) |
| 3 | PVE VM/LXC VLAN tags not fully set | VMs partially in wrong VLAN | Phase A4 |
