#!/bin/bash
# Backup all in-cluster databases.
# Usage:
#   ./scripts/backup-all-databases.sh
#
# Optional environment:
#   DB_BACKUP_DIR=/path/on/backup/disk
#   DB_BACKUP_EVIDENCE_DIR=/path/visible/to/backups-microservice
#   DB_BACKUP_RETENTION_DAYS=14
#   K8S_NAMESPACE=statex-apps
#   POSTGRES_DEPLOYMENT=db-server-postgres
#   REDIS_DEPLOYMENT=db-server-redis

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

K8S_NAMESPACE="${K8S_NAMESPACE:-statex-apps}"
POSTGRES_DEPLOYMENT="${POSTGRES_DEPLOYMENT:-db-server-postgres}"
REDIS_DEPLOYMENT="${REDIS_DEPLOYMENT:-db-server-redis}"
BACKUP_DIR="${DB_BACKUP_DIR:-$PROJECT_ROOT/backups}"
EVIDENCE_DIR="${DB_BACKUP_EVIDENCE_DIR:-$PROJECT_ROOT/backup-evidence}"
RETENTION_DAYS="${DB_BACKUP_RETENTION_DAYS:-14}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="$BACKUP_DIR/$TIMESTAMP"
MANIFEST="$RUN_DIR/manifest.txt"

log() {
    printf '%s\n' "$*"
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log "ERROR: required command not found: $1"
        exit 1
    fi
}

k8s_deployment_exists() {
    kubectl -n "$K8S_NAMESPACE" get "deploy/$1" >/dev/null 2>&1
}

backup_postgres_k8s() {
    local dump_file="$RUN_DIR/postgres_all_${TIMESTAMP}.sql.gz"
    local db_list_file="$RUN_DIR/postgres_databases.txt"

    log "Backing up PostgreSQL deployment $K8S_NAMESPACE/$POSTGRES_DEPLOYMENT"

    kubectl -n "$K8S_NAMESPACE" exec "deploy/$POSTGRES_DEPLOYMENT" -- sh -lc \
        'pg_isready -U "$POSTGRES_USER" -d "${POSTGRES_DB:-postgres}" >/dev/null'

    kubectl -n "$K8S_NAMESPACE" exec "deploy/$POSTGRES_DEPLOYMENT" -- sh -lc \
        'psql -U "$POSTGRES_USER" -d postgres -At -c "select datname from pg_database where datistemplate = false order by datname;"' \
        > "$db_list_file"

    kubectl -n "$K8S_NAMESPACE" exec "deploy/$POSTGRES_DEPLOYMENT" -- sh -lc \
        'pg_dumpall -U "$POSTGRES_USER" --clean --if-exists' \
        | gzip -9 > "$dump_file"

    gzip -t "$dump_file"
    log "PostgreSQL backup: $dump_file ($(du -h "$dump_file" | awk '{print $1}'))"
}

backup_redis_k8s() {
    local dump_file="$RUN_DIR/redis_${TIMESTAMP}.rdb.gz"

    if ! k8s_deployment_exists "$REDIS_DEPLOYMENT"; then
        log "Redis deployment $K8S_NAMESPACE/$REDIS_DEPLOYMENT not found; skipping"
        return 0
    fi

    log "Backing up Redis deployment $K8S_NAMESPACE/$REDIS_DEPLOYMENT"

    kubectl -n "$K8S_NAMESPACE" exec "deploy/$REDIS_DEPLOYMENT" -- sh -lc \
        'redis-cli ping >/dev/null'

    kubectl -n "$K8S_NAMESPACE" exec "deploy/$REDIS_DEPLOYMENT" -- sh -lc \
        'tmp="/tmp/codex-backup-redis.rdb"; rm -f "$tmp"; redis-cli --rdb "$tmp" >/dev/null; cat "$tmp"; rm -f "$tmp"' \
        | gzip -9 > "$dump_file"

    gzip -t "$dump_file"
    log "Redis backup: $dump_file ($(du -h "$dump_file" | awk '{print $1}'))"
}

prune_old_backups() {
    if [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] && [ "$RETENTION_DAYS" -gt 0 ]; then
        find "$BACKUP_DIR" -maxdepth 1 -type d -name '20??????_??????' -mtime +"$RETENTION_DAYS" -print -exec rm -rf {} \;
    fi
}

write_evidence_manifest() {
    mkdir -p "$EVIDENCE_DIR"
    chmod 700 "$EVIDENCE_DIR"

    python3 - "$RUN_DIR" "$BACKUP_DIR" "$EVIDENCE_DIR" "$TIMESTAMP" "$K8S_NAMESPACE" "$POSTGRES_DEPLOYMENT" "$REDIS_DEPLOYMENT" "$RETENTION_DAYS" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

run_dir, backup_dir, evidence_dir, timestamp, namespace, postgres_deployment, redis_deployment, retention_days = sys.argv[1:]
db_file = os.path.join(run_dir, "postgres_databases.txt")

try:
    with open(db_file, "r", encoding="utf-8") as handle:
        databases = [line.strip() for line in handle if line.strip()]
except FileNotFoundError:
    databases = []

artifacts = []
for name in sorted(os.listdir(run_dir)):
    if not name.endswith(".gz"):
        continue
    path = os.path.join(run_dir, name)
    kind = "postgres_logical_dump" if name.startswith("postgres_all_") else "redis_rdb" if name.startswith("redis_") else "artifact"
    artifacts.append({
        "name": name,
        "kind": kind,
        "size_bytes": os.path.getsize(path),
    })

manifest = {
    "schema_version": 1,
    "source": "database-server",
    "source_category": "postgres_database",
    "backup_type": "kubernetes_logical_export",
    "status": "success",
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "backup_timestamp": timestamp,
    "host": os.uname().nodename,
    "namespace": namespace,
    "postgres_deployment": postgres_deployment,
    "redis_deployment": redis_deployment,
    "storage": {
        "backup_dir": backup_dir,
        "run_dir": run_dir,
        "evidence_dir": evidence_dir,
        "retention_days": int(retention_days) if retention_days.isdigit() else retention_days,
    },
    "databases": databases,
    "database_count": len(databases),
    "artifacts": artifacts,
    "artifact_count": len(artifacts),
    "secret_policy": "No secret values, passwords, tokens, or dump contents are written to this evidence manifest.",
}

os.makedirs(evidence_dir, exist_ok=True)
current = os.path.join(evidence_dir, f"{timestamp}.json")
latest = os.path.join(evidence_dir, "latest.json")
for target in (current, latest):
    tmp = f"{target}.tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(tmp, target)
PY
}

require_command kubectl
require_command gzip
require_command python3

if ! k8s_deployment_exists "$POSTGRES_DEPLOYMENT"; then
    log "ERROR: PostgreSQL deployment $K8S_NAMESPACE/$POSTGRES_DEPLOYMENT not found"
    exit 1
fi

mkdir -p "$RUN_DIR"
chmod 700 "$RUN_DIR"

{
    log "backup_timestamp=$TIMESTAMP"
    log "host=$(hostname)"
    log "namespace=$K8S_NAMESPACE"
    log "postgres_deployment=$POSTGRES_DEPLOYMENT"
    log "redis_deployment=$REDIS_DEPLOYMENT"
    log "backup_dir=$RUN_DIR"
    log "retention_days=$RETENTION_DAYS"
} > "$MANIFEST"

backup_postgres_k8s
backup_redis_k8s
write_evidence_manifest
prune_old_backups

log "Backup completed: $RUN_DIR"
log "Evidence manifest: $EVIDENCE_DIR/latest.json"
