# Network

> Physical and logical network inventory, topology, and firewall design.
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
| 30 | 192.168.30.0/24 | DMZ | Externally exposed services |
| 40 | 192.168.40.0/24 | Untrust | IoT, WiFi SSID "IOT", Nvidia Shield, Hue Bridge |

> VLAN 1 is the UniFi native/default network. All 5 networks are configured with separate L2/L3 segments.

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

## PVE SDN Configuration

- `vmbr0` VLAN-aware: ✅ enabled on all nodes
- PVE management interface: ⚠️ currently on VLAN 10 (192.168.10.x) — interim state

### SDN Zone

| Zone | Type | Bridge | IPAM |
|------|------|--------|------|
| `homelab` | vlan | vmbr0 | pve |

### SDN VNETs

| VNET | VLAN Tag | Use |
|------|----------|-----|
| `Servers` | 10 | PVE VMs/LXCs, TrueNAS, k3s |
| `Clients` | 20 | Client endpoints |
| `DMZ` | 30 | Externally exposed services |
| `iot` | 40 | IoT, Untrust devices |

> Management VLAN 1 is not in SDN — PVE uses the native untagged network directly.
> VMs/LXCs should use the VNET name as bridge (e.g. `bridge=Servers`) instead of `vmbr0` directly.

Target after Phase 1.5 (P1.5-8 / P1.5-9):
- PVE mgmt interface: VLAN 1 (192.168.1.x — new static IPs)
- All VMs/LXCs: assigned to appropriate VNET (`Servers` for most)

---

## Firewall Design

> Inter-VLAN firewall rules for Unifi Dream Machine.
> Implemented in Phase 1.5 (P1.5-9) — after Tailscale is active (P1.5-6).

### Principle

Default deny between VLANs. Only explicitly allowed traffic passes.
Admin access to all VLANs via Tailscale (Pi 2 subnet router) — not via client device exceptions.

### Rules per VLAN

#### Management (VLAN 1 — 192.168.1.0/24)
| Direction | Target | Action | Reason |
|-----------|--------|--------|--------|
| Management → any | — | ✅ Allow | Admins need full access |
| any → Management | — | ❌ Block | No device initiates to management interfaces |

#### Server (VLAN 10 — 192.168.10.0/24)
| Direction | Target | Action | Reason |
|-----------|--------|--------|--------|
| Server → Internet | — | ✅ Allow | Updates, API calls, external services |
| Server → Server | — | ✅ Allow | Inter-service communication (k3s, etc.) |
| Server → Management | — | ❌ Block | Servers don't touch management interfaces |
| Server → Client / DMZ / Untrust | — | ❌ Block | Servers don't initiate to client networks |

#### Client (VLAN 20 — 192.168.20.0/24)
| Direction | Target | Action | Reason |
|-----------|--------|--------|--------|
| Client → Internet | — | ✅ Allow | Normal internet access |
| Client → Reverse Proxy / Ingress | Port 80, 443 | ✅ Allow | Reach self-hosted services (via ingress only) |
| Client → Server (direct) | — | ❌ Block | No direct access to service IPs, k3s nodes, TrueNAS |
| Client → Management | — | ❌ Block | No admin access from client devices |
| Client → Untrust | — | ❌ Block | Clients don't talk to IoT |

#### DMZ (VLAN 30 — 192.168.30.0/24)
| Direction | Target | Action | Reason |
|-----------|--------|--------|--------|
| DMZ → Internet | — | ✅ Allow | Reverse proxy, Cloudflare, external traffic |
| DMZ → any internal | — | ❌ Block | DMZ is isolated from internal network |

#### Untrust (VLAN 40 — 192.168.40.0/24)
| Direction | Target | Action | Reason |
|-----------|--------|--------|--------|
| Untrust → Internet | — | ✅ Allow | Normal internet access for IoT/WiFi |
| Untrust → any internal | — | ❌ Block | IoT/WiFi has no access to internal networks |

### Global Exceptions (all VLANs)

| From | To | Port | Reason |
|------|----|------|--------|
| All VLANs | AdGuard Home IPs (Pi 1 + Pi 2) | 53 TCP/UDP | DNS resolution |
| All VLANs | Internet | 123 UDP | NTP |

### Admin Access

All admin access (PVE, TrueNAS, AdGuard Home, etc.) via **Tailscale only**.
Pi 2 advertises all 5 subnets — connect via Tailscale to reach any device regardless of VLAN.

No client device exceptions in the firewall — if Tailscale is down, use a device physically
in the Management VLAN or connect a laptop directly to the management switch port.

---

## Open Issues

| # | Issue | Impact | When |
|---|-------|--------|------|
| 1 | No inter-VLAN firewall rules | All VLANs can reach each other | After Tailscale (Phase B) |
| 2 | PVE mgmt interface still on VLAN 10 (192.168.10.x) | PVE nodes not in Management VLAN | After Tailscale (Phase C) |
| 3 | PVE VM/LXC VLAN tags not fully set | VMs partially in wrong VLAN | Phase A4 |
