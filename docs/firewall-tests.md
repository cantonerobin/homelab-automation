# Firewall Test Handbook

Run this after every change in `terraform/unifi/`:
```bash
ansible-playbook ansible/playbooks/firewall-test.yml
```

---

## Test hosts per VLAN

| VLAN | Subnet | Host | IP |
|------|--------|------|----|
| MGMT (1) | 192.168.1.0/24 | pi01 | 192.168.1.2 |
| Server (10) | 192.168.10.0/24 | k3s-nova | 192.168.10.30 |
| DMZ (30) | 192.168.30.0/24 | nextcloud | 192.168.30.82 |
| DMZ (30) | 192.168.30.0/24 | mediastack | 192.168.30.62 |
| Client (20) | 192.168.20.0/24 | — | manual (192.168.20.100) |

---

## Test matrix

### ALLOW tests — connection must succeed

| ID | Rule | Source | Destination | Port | Expected |
|----|------|--------|-------------|------|----------|
| T01 | Allow MGMT→any | pi01 (1.2) | k3s-nova (10.30) | 22 | OPEN |
| T02 | Allow MGMT→any | pi01 (1.2) | nextcloud (30.82) | 22 | OPEN |
| T03 | Allow MGMT→any | pi01 (1.2) | mediastack (30.62) | 22 | OPEN |
| T04 | Allow DNS | k3s-nova (10.30) | pi01 (1.2) | 53 | OPEN |
| T05 | Allow DNS | nextcloud (30.82) | pi01 (1.2) | 53 | OPEN |
| T06 | Allow DNS | mediastack (30.62) | pi01 (1.2) | 53 | OPEN |
| T07 | Allow Server→DMZ | k3s-nova (10.30) | nextcloud (30.82) | 22 | OPEN |
| T08 | Allow Server→DMZ | k3s-nova (10.30) | mediastack (30.62) | 22 | OPEN |

### DENY tests — connection must time out

| ID | Rule | Source | Destination | Port | Expected |
|----|------|--------|-------------|------|----------|
| T09 | Default deny | k3s-nova (10.30) | pi01 (1.2) | 22 | TIMEOUT |
| T10 | Default deny | k3s-nova (10.30) | pi01 (1.2) | 80 | TIMEOUT |
| T11 | Default deny | nextcloud (30.82) | k3s-nova (10.30) | 22 | TIMEOUT |
| T12 | Default deny | nextcloud (30.82) | pi01 (1.2) | 22 | TIMEOUT |
| T13 | Default deny | mediastack (30.62) | k3s-nova (10.30) | 22 | TIMEOUT |
| T14 | Default deny | mediastack (30.62) | pi01 (1.2) | 22 | TIMEOUT |

### Manual tests — Client VLAN (no Ansible host)

From your workstation (192.168.20.100):
```bash
# T15 ALLOW: Client → DMZ
nc -zv -w 3 192.168.30.82 443   # nextcloud  — expected: OPEN
nc -zv -w 3 192.168.30.62 80    # mediastack — expected: OPEN

# T16 DENY: Client → Server
nc -zv -w 3 192.168.10.30 22    # k3s-nova — expected: TIMEOUT

# T17 DENY: Client → MGMT
nc -zv -w 3 192.168.1.2 22      # pi01 — expected: TIMEOUT
```

---

## Notes

- **TIMEOUT vs REFUSED**: DROP rules cause timeouts (no RST). An immediate
  "Connection refused" means the host is reachable but the port is closed —
  that is a misconfiguration if TIMEOUT was expected.
- **DNS port 53 TCP**: Tested via nc (TCP). Also verify UDP manually:
  `dig @192.168.1.2 google.com`
- **Established/related**: Return traffic from allowed sessions is always
  permitted (rule 20010). DENY tests only verify *initiated* connections.
- **New rule added?** Add a test row here and a corresponding task in the
  playbook before merging the Terraform change.
