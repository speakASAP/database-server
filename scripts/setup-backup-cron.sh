#!/bin/bash
# Setup Automated Daily Backups
# Usage: ./scripts/setup-backup-cron.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

CRON_JOB="0 2 * * * cd $PROJECT_ROOT && $PROJECT_ROOT/scripts/backup-all-databases.sh >> $PROJECT_ROOT/logs/backup.log 2>&1"

echo "📅 Setting up daily backup cron job..."
echo "   Schedule: Daily at 2:00 AM"
echo "   Script: $PROJECT_ROOT/scripts/backup-all-databases.sh"
echo ""

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "backup-all-databases.sh"; then
    echo "⚠️  Backup cron job already exists"
    read -p "Do you want to update it? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "❌ Cancelled"
        exit 0
    fi
    # Remove existing job
    crontab -l 2>/dev/null | grep -v "backup-all-databases.sh" | crontab -
fi

# Add new cron job
(crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

if [ $? -eq 0 ]; then
    echo "✅ Backup cron job added successfully"
    echo ""
    echo "📋 Current cron jobs:"
    crontab -l | grep backup-all-databases.sh
    echo ""
    echo "💡 To remove: crontab -e (then delete the backup line)"
    echo "💡 To test: ./scripts/backup-all-databases.sh"
else
    echo "❌ Failed to add cron job"
    exit 1
fi

