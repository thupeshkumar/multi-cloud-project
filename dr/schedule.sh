#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
mkdir -p "$HERE/logs"
while true; do
 echo "$(date -u +%FT%TZ) Backup cycle started"
 if bash "$HERE/backup.sh" >> "$HERE/logs/backup.log" 2>&1; then
  echo "Backup completed"
 else
  echo "BACKUP FAILED: inspect logs/backup.log" >&2
 fi
 sleep 900
done
