# Second Disk Database Backup Runbook

## Intent Preservation Chain

- Vision: protect Alfares infrastructure databases from loss if the primary data disk fails.
- Goal Impact: keep restorable PostgreSQL and Redis backups on a different physical disk from the live database volumes.
- System: `database-server` in Kubernetes namespace `statex-apps`.
- Feature: nightly database export with retention and restore-ready artifacts surfaced in `backups-microservice`.
- Task: run `scripts/backup-all-databases.sh` to the second-disk backup directory.
- Execution Plan: use the verified `/dev/md0` mount at `/srv/critical-backups`, point `DB_BACKUP_DIR` at an isolated `database-server` subdirectory, install cron, run a test backup, and verify gzip integrity plus frontend evidence.
- Coding Prompt: update legacy Docker-only backup scripts to use the current Kubernetes deployments.
- Code: `scripts/backup-all-databases.sh`, `scripts/backup-database.sh`, `scripts/list-databases.sh`, `scripts/setup-backup-cron.sh`, `backups-microservice` external evidence UI.
- Validation: backup command must create gzip-valid PostgreSQL and Redis artifacts plus sanitized `backup-evidence/latest.json` visible through `/dashboard/summary`.

## Current Disk Findings

- Live root and Kubernetes local-path data are on `/dev/sda2`.
- Git working trees and `/home/ssf/Documents/Github` are on `/dev/nvme0n1p1` through `/mnt/docker-data`.
- The second-disk backup filesystem is `/dev/md0`, mounted read-write at `/srv/critical-backups`.
- `/dev/md0` is a degraded RAID1 currently backed by `sdb2` (`[U_]` in `/proc/mdstat`). This protects against the primary database disk failing, but it is not a healthy two-member mirror until the missing RAID member is repaired.
- `/srv/critical-backups/alfares-critical` is owned by the root-managed Vault/K3s critical backup service. Do not modify it from database backup jobs.
- Database backups use only `/srv/critical-backups/database-server`, owned by `ssf:ssf` with mode `700`.

## Coordination With Root Critical Backups

Before running a manual database backup or changing the backup directory, confirm the root critical backup service is not active:

```bash
systemctl is-active alfares-critical-backup.service || true
findmnt -T /srv/critical-backups -o TARGET,SOURCE,FSTYPE,SIZE,USED,AVAIL,OPTIONS
cat /proc/mdstat
```

If `alfares-critical-backup.service` is `activating` or a `tar`/`openssl enc` process is writing under `/srv/critical-backups/alfares-critical`, wait for it to finish before starting a database dump.

## Root-Gated Directory Setup

These steps require root or sudo and should not remount `/dev/md0` because it is already mounted at `/srv/critical-backups`:

```bash
findmnt -T /srv/critical-backups
install -d -m 700 -o ssf -g ssf /srv/critical-backups/database-server
ls -ld /srv/critical-backups/database-server
```

Do not mount `/dev/md0` again at `/mnt/alfares-db-backups`; that would conflict with the existing critical-backup mountpoint.

## Enable Nightly Backups

```bash
cd /home/ssf/Documents/Github/database-server
DB_BACKUP_DIR=/srv/critical-backups/database-server DB_BACKUP_RETENTION_DAYS=14 ./scripts/setup-backup-cron.sh
```

Installed cron:

```cron
0 2 * * * DB_BACKUP_DIR=/srv/critical-backups/database-server DB_BACKUP_RETENTION_DAYS=14 cd /home/ssf/Documents/Github/database-server && /home/ssf/Documents/Github/database-server/scripts/backup-all-databases.sh >> /home/ssf/Documents/Github/database-server/logs/backup.log 2>&1
```

## Manual Validation

```bash
cd /home/ssf/Documents/Github/database-server
DB_BACKUP_DIR=/srv/critical-backups/database-server DB_BACKUP_RETENTION_DAYS=14 ./scripts/backup-all-databases.sh
find /srv/critical-backups/database-server -maxdepth 2 -type f -name '*.gz' -exec gzip -t {} \;
python3 -m json.tool /home/ssf/Documents/Github/database-server/backup-evidence/latest.json
```

Latest validated run on 2026-06-25:

- Run directory: `/srv/critical-backups/database-server/20260625_190924`
- PostgreSQL artifact: `postgres_all_20260625_190924.sql.gz`, 401039168 bytes
- Redis artifact: `redis_20260625_190924.rdb.gz`, 1748 bytes
- Database count: 38
- Artifact count: 2
- Frontend API evidence: `external_evidence.database_server.status=success`, `backup_dir=/srv/critical-backups/database-server`

## Restore Notes

The current backup is a logical PostgreSQL cluster export from `pg_dumpall --clean --if-exists` plus a Redis RDB export. Before restore, copy the selected run directory off `/srv/critical-backups`, verify `gzip -t`, and restore into a fresh PostgreSQL/Redis target rather than over live production without a separate restore plan.
