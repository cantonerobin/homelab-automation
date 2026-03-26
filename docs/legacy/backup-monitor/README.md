# Backup Monitor / Migration Scripts

## Scripts

### `synology-rsync-migration.sh`
Synology → externe HDD Migration (erledigt, Mar 2025).
Startet pro Unterverzeichnis einen separaten rsync Job (`--whole-file --inplace`).

### `synology-backup-monitor.sh`
Überwacht laufende rsync Jobs und sendet Gotify Notifications (Fortschritt, Hang-Detection, Fertig).
Wurde per Cron alle 30min ausgeführt während der Synology-Migration.

### `truenas-media-restore.sh`
Restore ext. HDD → TrueNAS NFS Share (P1-11).

**Quelle:** `/mnt/backup-restore/media-backup/media/`
**Ziel:** `/mnt/data/mediastack/mediastack-data/`

- Pro Verzeichnis ein separater rsync Job
- TV wird zuerst gestartet (Priorität)
- Auto-Restart bei Abbruch (max. 10 Versuche, 30s Pause)
- Gotify Notifications: Start, alle 30min Fortschritt + ETA, pro Dir fertig, Gesamtfertig
- rsync Flags: `-a --whole-file --inplace --info=progress2 --no-group`

**Ausführen (immer in screen — überlebt SSH-Disconnect):**
```bash
screen -S restore
bash truenas-media-restore.sh
# Ctrl+A D zum Detachen
screen -r restore   # wieder verbinden
```

**Logs:**
```bash
tail -f /root/rsync-restore-logs/tv.log
tail -f /root/rsync-restore-logs/movies.log
tail -f /root/rsync-restore-logs/*.log
```

**Snapshots während Migration deaktivieren:**
TrueNAS UI → Data Protection → Periodic Snapshot Tasks → Tasks für `mediastack-data` deaktivieren.
Nach Abschluss wieder aktivieren + manuell ersten Snapshot triggern.

**Gotify:** `https://notifications.cantone.net` — Token im Script.
