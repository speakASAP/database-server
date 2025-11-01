#!/bin/bash
# Restart Database Server
# Usage: ./scripts/restart.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔄 Restarting Database Server..."

"$SCRIPT_DIR/stop.sh"
sleep 2
"$SCRIPT_DIR/start.sh"

