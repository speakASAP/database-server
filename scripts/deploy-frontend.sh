#!/bin/bash
# Deploys database-server-frontend ONLY. See ../deploy.config.sh for scope.
# scripts/deploy.sh remains the datastore path (db-server-postgres/redis) and
# is deliberately left alone — do not merge the two.
set -euo pipefail
exec "$(dirname "$0")/../../shared/scripts/deploy.sh" "$(basename "$(cd "$(dirname "$0")/.." && pwd)")" "$@"
