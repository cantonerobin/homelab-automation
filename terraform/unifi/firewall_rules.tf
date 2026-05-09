# Inter-VLAN firewall rules — LAN_IN
# UCG Ultra user-defined rule range: 20000–29999
#
# Structure:
#   20000–20999  ALLOW rules (explicit permits)
#   29000        Default DENY — drop all remaining inter-VLAN traffic

# ── 20000: DEV - Anti Lockout Rule ──────────────────────────────────────────────────
resource "unifi_firewall_rule" "dev_anti_lockout_rule" {
  name       = "DEV - Anti Lockout Rule"
  action     = "accept"
  ruleset    = "LAN_IN"
  rule_index = 20000
  protocol   = "all"

  src_address = "192.168.20.100"
}

# ── 20010: Allow established/related (stateful baseline) ─────────────────────
resource "unifi_firewall_rule" "allow_established" {
  name       = "Allow established and related"
  action     = "accept"
  ruleset    = "LAN_IN"
  rule_index = 20010
  protocol   = "all"

  state_established = true
  state_related     = true
}


# ── 20101: Allow MGMT → any ──────────────────────────────────────────────────
resource "unifi_firewall_rule" "allow_mgmt_to_any" {
  name       = "Allow MGMT to any"
  action     = "accept"
  ruleset    = "LAN_IN"
  rule_index = 20101
  protocol   = "all"

  src_firewall_group_ids = [unifi_firewall_group.network_mgmt.id]
}

# ── 20200: Allow any → DNS (pi01/pi02 port 53) ───────────────────────────────
resource "unifi_firewall_rule" "allow_dns" {
  name       = "Allow ANY to hosts_dns"
  action     = "accept"
  ruleset    = "LAN_IN"
  rule_index = 20200
  protocol   = "tcp_udp"

  dst_firewall_group_ids = [unifi_firewall_group.hosts_dns-server.id]
  dst_port               = "53"
}

# ── 20300: Allow Server → DMZ ────────────────────────────────────────────────
resource "unifi_firewall_rule" "allow_server_to_dmz" {
  name       = "Allow Server to DMZ"
  action     = "accept"
  ruleset    = "LAN_IN"
  rule_index = 20300
  protocol   = "all"

  src_firewall_group_ids = [unifi_firewall_group.network_server.id]
  dst_firewall_group_ids = [unifi_firewall_group.network_dmz.id]
}

# ── 20400: Allow Client → DMZ ────────────────────────────────────────────────
resource "unifi_firewall_rule" "allow_client_to_dmz" {
  name       = "Allow Client to DMZ"
  action     = "accept"
  ruleset    = "LAN_IN"
  rule_index = 20400
  protocol   = "all"

  src_firewall_group_ids = [unifi_firewall_group.network_client.id]
  dst_firewall_group_ids = [unifi_firewall_group.network_dmz.id]
}

# ── 20500: Allow k3s VLAN5 cluster-internal traffic ──────────────────────────
resource "unifi_firewall_rule" "allow_k3s_cluster" {
  name       = "Allow k3s cluster internal"
  action     = "accept"
  ruleset    = "LAN_IN"
  rule_index = 20500
  protocol   = "all"

  src_firewall_group_ids = [unifi_firewall_group.network_k3s.id]
  dst_firewall_group_ids = [unifi_firewall_group.network_k3s.id]
}

# ── 29000: Default DENY — drop all remaining inter-VLAN traffic ──────────────
resource "unifi_firewall_rule" "default_deny" {
  name       = "Default deny inter-VLAN"
  action     = "drop"
  ruleset    = "LAN_IN"
  rule_index = 21000
  protocol   = "all"

  dst_firewall_group_ids = [unifi_firewall_group.network_all.id]
}
