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

### `lookup('file', playbook_dir + '/../..')` — path depth changes after Ansible refactor

After the Ansible restructure from `ansible/truenas/` to `ansible/playbooks/truenas/`, `playbook_dir`
is now 3 levels deep from repo root instead of 2. Fix all relative lookups:

```yaml
# Wrong (after refactor to ansible/playbooks/truenas/)
lookup('file', playbook_dir + '/../../ssh/truenas-hetzner')
# → resolves to ansible/ssh/truenas-hetzner ❌

# Correct
lookup('file', playbook_dir + '/../../../ssh/truenas-hetzner')
# → resolves to ssh/truenas-hetzner (repo root) ✅
```

---

### `error in libcrypto` when Ansible copies SSH key to remote host

**Symptom:** Ansible writes SSH private key content via `copy: content: "{{ var }}"` to a remote host.
Remote SSH client then fails with:
```
Load key "/tmp/key": error in libcrypto
```

**Root cause:** The key content is read via `lookup('file', ...)` from the Windows NTFS filesystem
(`/mnt/c/...`). The content may be mangled (line endings or encoding) when passed through Ansible's
variable pipeline to the `copy` module.

**Workaround:** Pre-create remote directories directly from the controller (not via the remote host).
The mkdir block in the playbook has `ignore_errors: true` so the rest continues regardless.

**When is manual mkdir required?**

| Task type | mkdir needed? | Why |
|-----------|--------------|-----|
| PUSH (backup) | ❌ No | rclone creates remote dirs automatically on first sync |
| PULL (restore) | ✅ Yes | TrueNAS validates `attributes.folder` exists at task creation time — fails with `[EINVAL] Directory does not exist` if not |

**Adding a new dataset to cloud sync** (while Playbook mkdir is broken):
```bash
# Step 1: pre-create remote dir on Hetzner from controller
ssh -i ~/.ssh/truenas-hetzner -p 23 u568390@u568390.your-storagebox.de \
  "mkdir -p backups/<new-dataset>"

# Step 2: add entry to cloudsync_tasks + cloudsync_restore_tasks in config.yml, then:
ansible-playbook ansible/playbooks/truenas/cloudsync.yml --tags tasks \
  --private-key ~/.ssh/ansible -e cloud_cred_id=2
```

The `cloud_cred_id=2` is required when running with `--tags tasks` because it bypasses
`cloudsync_credentials.yml` which normally sets that variable.

---

### rclone crypt `bad PKCS#7 padding` — password mismatch between PUSH and PULL tasks

**Symptom:** PULL (restore) task runs, reports SUCCESS, but restores nothing. Log shows:
```
Skipping undecryptable file name: bad PKCS#7 padding - too long
Skipping undecryptable dir name: bad PKCS#7 padding - not all the same
There was nothing to transfer
```

**Root cause:** The PUSH task was created before `secrets.yml` was rotated (2026-04-10). When
credentials were rotated, `secrets.yml` was updated but the existing PUSH task was never recreated —
it kept running with the old passwords. New tasks (PULL/restore) created from the updated
`secrets.yml` used different passwords, so decryption failed silently.

**Important:** TrueNAS stores `encryption_password` as plaintext in the database. `rclone reveal`
will fail on these values — they are NOT rclone-obscured, they are the actual plain text passwords.

**Diagnose:** Compare passwords across all tasks:
```bash
ssh -i ~/.ssh/ansible root@truenas 'midclt call cloudsync.query' | python3 -c "import json,sys; [print(t['id'], t.get('encryption_password','')[:20], t['description'][:30]) for t in json.load(sys.stdin)]"
```

**Fix:** Update affected tasks with the correct password, then re-run the PUSH task to re-encrypt
all remote data with the new password:
```bash
# Update PUSH task with correct passwords from secrets.yml
ssh -i ~/.ssh/ansible root@truenas "midclt call cloudsync.update 5 '{\"encryption_password\": \"<pw>\", \"encryption_salt\": \"<salt>\"}'"

# Re-sync: rclone will delete old-encrypted files and upload new-encrypted files
ssh -i ~/.ssh/ansible root@truenas 'midclt call --job cloudsync.sync 5'
```

**Prevention:** When rotating rclone crypt credentials, always delete and recreate ALL cloud sync
tasks (PUSH + PULL) via the Ansible playbook with the new credentials. Running with stale tasks
means data is encrypted with leaked/old passwords.

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

## Ceph OSD Disk Selection

**Session:** 2026-04-24 — helix NVMe SMART FAILED, nova NVMe 86% worn

### Kingston SNV3S unsuitable for Ceph OSD

**Symptom:** Both Kingston SNV3S1000G drives (helix + nova) failed/degraded prematurely:
- helix: 21 TB host writes → `Percentage Used: 100%`, `SMART FAILED`
- nova: 18 TB host writes → `Percentage Used: 86%`
- vega: WD WDS100T2B0C — 35 TB host writes → `Percentage Used: 8%` (same cluster, same workload)

**Root cause:** Ceph OSD write amplification (10–30×). For every 1 TB of host writes, the NVMe NAND sees 10–30 TB of actual program cycles. The Kingston SNV3S is a budget QLC/TLC drive with low rated TBW — insufficient for Ceph OSD duty.

**Rule:** Never use budget/consumer NVMe drives (Kingston NV3/SNV3S, Crucial P3, WD Green) as Ceph OSDs. Use NAS/server-grade NVMe (WD Red SN700, Samsung 970 EVO Plus, or any drive with ≥600 TBW rated for 1TB).

---

### Ceph OSD failure cascades to PVE node panics

**Symptom:** nova crashed (kernel panic, no warning) while helix's OSD disk was failing. nova was down 5 days.

**Root cause:** helix's Kingston NVMe had IO errors → Ceph cluster degraded → RBD devices on nova (ceph_data-backed VMs/LXCs) experienced IO timeouts → kernel watchdog timeout → panic. Last log entry before crash was a smartd NVMe error, no `blk_update_request` or `hung_task` in logs (crash was instantaneous).

**Fix:** Evict the failing OSD immediately. Once helix OSD was purged, cluster stabilised on nova + vega with no further crashes.

**Rule:** Any Ceph OSD health degradation (SMART warnings, high error counts) is an urgent cluster-wide risk — not just a disk replacement task. A failing OSD can crash PVE nodes that have active RBD mounts.

---

### Samsung MZVLB256HAHQ (PM981) APST crash on Linux/PVE

**Symptom:** nova crashed at exactly the moment smartd logged an NVMe error on `/dev/nvme1` (Samsung OS disk). 2686 accumulated error log entries (status `0x4004`, NSID 0+1).

**Root cause:** Samsung PM981-series NVMe drives have known issues with Autonomous Power State Transitions (APST) on Linux. The NVMe controller enters a power state that triggers command timeouts → kernel panic on OS disk IO errors.

**Affected drives:** Samsung MZVLB256HAHQ-000H1 (PM981, 256GB) — present on helix and nova as OS disks.

**Fix:**
```bash
# /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT="quiet nvme_core.default_ps_max_latency_us=0"
update-grub
```

Disables APST — forces NVMe to stay in active power state. No performance impact on server workloads.

**Status:** Not yet applied on nova or helix. Apply before/during Phase 2 reinstall.

---

## rclone crypt

Encryption passwords for Hetzner offsite backup are in `ansible/truenas/vars/secrets.yml` (gitignored).
Back up `hetzner_rclone_encryption_password` and `hetzner_rclone_encryption_salt` in Proton Pass.
Without these two values, data on Hetzner Storage Box is unrecoverable.
