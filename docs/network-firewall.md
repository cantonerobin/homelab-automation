# Network — Firewall Design

> Inter-VLAN firewall rules for Unifi Dream Machine.
> Implemented in Phase 1.5 (P1.5-9) — after Tailscale is active (P1.5-6).
> Last updated: 2026-03-29

---

## Principle

Default deny between VLANs. Only explicitly allowed traffic passes.
Admin access to all VLANs via Tailscale (Pi 2 subnet router) — not via client device exceptions.

---

## Rules per VLAN

### Management (VLAN 2 — 192.168.1.0/24)
| Direction | Target | Action | Reason |
|-----------|--------|--------|--------|
| Management → any | — | ✅ Allow | Admins need full access |
| any → Management | — | ❌ Block | No device initiates to management interfaces |

### Server (VLAN 10 — 192.168.10.0/24)
| Direction | Target | Action | Reason |
|-----------|--------|--------|--------|
| Server → Internet | — | ✅ Allow | Updates, API calls, external services |
| Server → Server | — | ✅ Allow | Inter-service communication (k3s, etc.) |
| Server → Management | — | ❌ Block | Servers don't touch management interfaces |
| Server → Client / DMZ / Untrust | — | ❌ Block | Servers don't initiate to client networks |

### Client (VLAN 20 — 192.168.20.0/24)
| Direction | Target | Action | Reason |
|-----------|--------|--------|--------|
| Client → Internet | — | ✅ Allow | Normal internet access |
| Client → Reverse Proxy / Ingress | Port 80, 443 | ✅ Allow | Reach self-hosted services (via ingress only) |
| Client → Server (direct) | — | ❌ Block | No direct access to service IPs, k3s nodes, TrueNAS |
| Client → Management | — | ❌ Block | No admin access from client devices |
| Client → Untrust | — | ❌ Block | Clients don't talk to IoT |

### DMZ (VLAN 30 — 192.168.30.0/24)
| Direction | Target | Action | Reason |
|-----------|--------|--------|--------|
| DMZ → Internet | — | ✅ Allow | Reverse proxy, Cloudflare, external traffic |
| DMZ → any internal | — | ❌ Block | DMZ is isolated from internal network |

### Untrust (VLAN 40 — 192.168.40.0/24)
| Direction | Target | Action | Reason |
|-----------|--------|--------|--------|
| Untrust → Internet | — | ✅ Allow | Normal internet access for IoT/WiFi |
| Untrust → any internal | — | ❌ Block | IoT/WiFi has no access to internal networks |

---

## Global Exceptions (all VLANs)

| From | To | Port | Reason |
|------|----|------|--------|
| All VLANs | AdGuard Home IPs (Pi 1 + Pi 2) | 53 TCP/UDP | DNS resolution |
| All VLANs | Internet | 123 UDP | NTP |

---

## Admin Access

All admin access (PVE, TrueNAS, AdGuard Home, etc.) via **Tailscale only**.
Pi 2 advertises all 5 subnets — connect via Tailscale to reach any device regardless of VLAN.

No client device exceptions in the firewall — if Tailscale is down, use a device physically
in the Management VLAN or connect a laptop directly to the management switch port.
