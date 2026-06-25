#!/bin/bash
# List in-cluster PostgreSQL databases without printing secrets.
# Usage: ./scripts/list-databases.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

K8S_NAMESPACE="${K8S_NAMESPACE:-statex-apps}"
POSTGRES_DEPLOYMENT="${POSTGRES_DEPLOYMENT:-db-server-postgres}"

if ! kubectl -n "$K8S_NAMESPACE" get "deploy/$POSTGRES_DEPLOYMENT" >/dev/null 2>&1; then
    echo "ERROR: PostgreSQL deployment $K8S_NAMESPACE/$POSTGRES_DEPLOYMENT not found"
    exit 1
fi

echo "Databases in $K8S_NAMESPACE/$POSTGRES_DEPLOYMENT:"
echo "=================================================="

kubectl -n "$K8S_NAMESPACE" exec "deploy/$POSTGRES_DEPLOYMENT" -- sh -lc '
psql -U "$POSTGRES_USER" -d postgres -c "
SELECT
    datname AS \"Database\",
    pg_size_pretty(pg_database_size(datname)) AS \"Size\",
    (SELECT count(*) FROM pg_stat_activity WHERE datname = d.datname) AS \"Connections\"
FROM pg_database d
WHERE datistemplate = false
ORDER BY pg_database_size(datname) DESC;
"
'
