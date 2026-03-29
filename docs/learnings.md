# Homelab — Learnings & Troubleshooting Notes

> Lessons learned from debugging sessions. Consult before troubleshooting similar issues.
> Language: English only.

---

## TrueNAS Cloud Sync (SFTP + rclone crypt)

**Session:** 2026-03-28 — P1-29 Hetzner offsite backup setup

### `pass` field must be `""` not `null`

**Symptom:** Cloud Sync task runs, immediately fails with:
```
AttributeError: 'NoneType' object has no attribute 'encode'
Traceback: cloud_sync.py → rclone() → RcloneConfig.__aenter__() →
  config["pass"] = rclone_encrypt_password(config["pass"])
```

**Root cause:** TrueNAS always calls `rclone_encrypt_password()` on the `pass` field regardless of
whether key-based auth is used. If `pass` is `null`/`None` (the default when not set), this crashes.

**Fix:** Always set `"pass": ""` (empty string) in the SFTP provider when creating or updating credentials:
```bash
midclt call cloudsync.credentials.create '{"name": "...", "provider": {"type": "SFTP", ..., "pass": "", "private_key": <id>}}'
```

---

### `private_key` in SFTP credentials must be an integer (keychain ID)

**Symptom:** Creating SFTP credential with private key content as string fails:
```
[EINVAL] cloud_sync_credentials_create.provider.SFTP.private_key: Input should be a valid integer
```

**How it works:**
1. Create a keychain credential of type `SSH_KEY_PAIR`:
   ```bash
   midclt call keychaincredential.create '{"name": "...", "type": "SSH_KEY_PAIR", "attributes": {"private_key": "<pem>", "public_key": "<pub>"}}'
   ```
2. Use the returned integer ID as `private_key` in the SFTP cloud credential.

**Wrong:** `"private_key": "-----BEGIN OPENSSH PRIVATE KEY-----..."` → rejected
**Correct:** `"private_key": 2` (integer keychain credential ID) → accepted

---

### Cloud Sync task credential reference becomes stale after credential delete/recreate

**Symptom:** Task was created successfully, credential was later deleted and recreated (new ID), task still runs but fails because it references the old (deleted) credential ID.

**Fix:** Delete and recreate the Cloud Sync task after recreating the credential. The playbook handles this idempotently — delete the task manually, then re-run `ansible-playbook ansible/truenas/cloudsync.yml`.

**Diagnose stale reference:**
```bash
midclt call cloudsync.credentials.query | python3 -c "import json,sys; [print('Cred ID:', c['id'], c['name']) for c in json.load(sys.stdin)]"
midclt call cloudsync.query | python3 -c "import json,sys; [print('Task:', t['description'], '| cred:', t['credentials']['id']) for t in json.load(sys.stdin)]"
```

---

### SSH key normalization (Windows line endings)

When Ansible reads the private key file from a Windows filesystem via `lookup('file', ...)`, the key may
contain `\r\n` line endings. Always normalize in the shell task before storing in keychain:

```bash
PRIVATE_KEY=$(python3 -c "
import json
content = open('/tmp/key').read().replace('\r\n', '\n').replace('\r', '\n')
print(json.dumps(content))
")
```

---

### midclt Python pipe — no indentation

**Symptom:**
```
IndentationError: unexpected indent
BrokenPipeError: [Errno 32] Broken pipe
```

**Fix:** Use single-line Python with semicolons when piping to `python3 -c`:
```bash
# Wrong — indented heredoc fails
midclt call foo.query | python3 -c "
  import json,sys
  ..."

# Correct — single line
midclt call foo.query | python3 -c "import json,sys; [print(c['id']) for c in json.load(sys.stdin)]"
```

---

### `midclt call --job cloudsync.sync <id>` — Ctrl+C is safe

`Ctrl+C` only disconnects the CLI client. The job continues running in the background on TrueNAS.
Monitor progress in the TrueNAS UI under **Data Protection → Cloud Sync Tasks**.

---

### `snapshot: true` — TrueNAS takes ZFS snapshot before sync

Add `"snapshot": true` to `cloudsync.create` / `cloudsync.update` to make TrueNAS automatically
take a ZFS snapshot of the source dataset before syncing. This ensures a consistent point-in-time
copy (no files changing mid-transfer).

Update existing task:
```bash
midclt call cloudsync.update <id> '{"snapshot": true}'
```

---

### SFTP provider format — `provider` must be a dict, not a string

**Wrong:**
```json
{"name": "...", "provider": "SFTP", "attributes": {"host": "..."}}
```

**Correct:**
```json
{"name": "...", "provider": {"type": "SFTP", "host": "...", "port": 23, "user": "...", "pass": "", "private_key": 2}}
```

---

## TrueNAS Ansible (general)

> See also: `ansible/truenas/configure.yml` inline comments and MEMORY.md for full list.

### `midclt call` JSON — always use `shell` + python3 for complex types

`to_json` Jinja2 filter serializes integers as strings in some cases. For `volsize`, `vm` ID, and other
integer fields, build the JSON string manually with integers directly embedded:

```yaml
- name: Create zvol
  shell: >
    midclt call pool.dataset.create
    '{"name": "data/foo", "type": "VOLUME", "volsize": {{ size_bytes | int }}, ...}'
```

### `interface.update` — removing DHCP requires explicit flags

Setting `aliases: []` alone does NOT remove a DHCP-assigned IP. Must explicitly set:
```json
{"ipv4_dhcp": false, "ipv6_auto": false, "aliases": []}
```

---

## SSH Keys

### Separate key per use case

| Key | Path | Purpose |
|-----|------|---------|
| `ssh/ansible` | gitignored | Ansible → all VMs + TrueNAS |
| `ssh/truenas-hetzner` | gitignored | TrueNAS → Hetzner Storage Box sync |

Both private keys must be backed up in Proton Pass (Secure Notes). See B-46.

---

## TrueNAS ZFS ARC Memory Pressure

**Session:** 2026-03-29 — intermittent Plex UI hangs + TrueNAS WebUI dropouts

### Symptoms

- Plex UI hangs intermittently
- TrueNAS WebUI periodically unreachable
- Complete connection drops

### Excluded causes

- NIC (RTL8168h / r8169) — no errors in operation
- ZFS pool I/O errors — all pools ONLINE, clean
- OOM kills — none
- STP delays on br1 — only at boot, not runtime

### Root cause

ZFS ARC without an explicit limit. Default `c_max ≈ 61.7 GB` (kernel sets this to ~total_RAM),
leaving only ~9 GB for host OS + TrueNAS middleware after ARC (~39 GB) + bhyve VM (16 GB fixed).

Under host-side memory pressure, ZFS ARC has to evict pages, which causes brief latency spikes
across the entire host — explaining the UI hangs and connection drops without any OOM events.

**Important:** the Plex VM has a *fixed* 16 GB allocation (no ballooning). bhyve locks these pages
at VM start — the VM does not dynamically compete with ARC at runtime. The issue is purely
host-side headroom for OS + services (~9 GB was not enough).

### Fix (applied 2026-03-29, temporary until reboot)

```bash
echo 25769803776 | sudo tee /sys/module/zfs/parameters/zfs_arc_max
# ARC limit: 24 GB
```

Memory split after fix: 24 GB ARC + 16 GB VM (fixed) + ~24 GB host = comfortable headroom.

### Make persistent (TODO — not yet done)

Via TrueNAS WebUI: **System → Advanced → ARC Max Size** → set to 25769803776 bytes (24 GB)

Or via midclt:
```bash
midclt call system.advanced.update '{"arc_max": 25769803776}'
```

Verify current ARC stats:
```bash
arc_summary | grep -E "c_max|size"
# or
cat /proc/spl/kstat/zfs/arcstats | grep -E "^c |^c_max|^size"
```

---

## rclone crypt

Encryption passwords for Hetzner offsite backup are in `ansible/truenas/vars/secrets.yml` (gitignored).
Back up `hetzner_rclone_encryption_password` and `hetzner_rclone_encryption_salt` in Proton Pass.
Without these two values, data on Hetzner Storage Box is unrecoverable.
