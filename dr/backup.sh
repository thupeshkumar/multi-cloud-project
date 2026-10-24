#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
mkdir -p "$HERE/backups"
exec 9>"$HERE/.backup.lock"
flock -n 9 || { echo "Another backup is running"; exit 1; }
RUN="$(date -u +%Y%m%dT%H%M%SZ)-$$"
DIR="$HERE/backups/$RUN"
mkdir "$DIR"
date -u +%FT%TZ > "$DIR/backup-started.txt"
ssh "${SSH[@]}" "$SOURCE_HOST" \
 "sudo -n docker exec '$SOURCE_CONTAINER' pg_dump -U '$SOURCE_USER' -d '$SOURCE_DB' -Fc --no-owner --no-acl" \
 > "$DIR/projectdb.dump.partial"
test -s "$DIR/projectdb.dump.partial"
mv "$DIR/projectdb.dump.partial" "$DIR/projectdb.dump"
ssh "${SSH[@]}" "$SOURCE_HOST" \
 "sudo -n docker exec -i '$SOURCE_CONTAINER' pg_restore --list" \
 < "$DIR/projectdb.dump" > "$DIR/archive-list.txt"
# Freeze writes to this dummy table during the backup/validation exercise.
ssh "${SSH[@]}" "$SOURCE_HOST" \
 "sudo -n docker exec '$SOURCE_CONTAINER' psql -X -q -v ON_ERROR_STOP=1 -U '$SOURCE_USER' -d '$SOURCE_DB' -c 'COPY (SELECT id,message FROM public.dr_evidence ORDER BY id) TO STDOUT WITH CSV HEADER'" \
 > "$DIR/expected.csv"
(cd "$DIR"; sha256sum projectdb.dump expected.csv backup-started.txt archive-list.txt > SHA256SUMS)
echo "$RUN" > "$DIR/COMPLETE"
copy_to() {
 local provider="$1" f
 for f in projectdb.dump expected.csv backup-started.txt archive-list.txt SHA256SUMS COMPLETE; do
  case "$provider" in
   aws) aws s3 cp "$DIR/$f" "s3://$AWS_BUCKET/sprint4/$RUN/$f" --only-show-errors ;;
   azure) az storage blob upload --auth-mode login --account-name "$AZURE_STORAGE_ACCOUNT" --container-name "$AZURE_CONTAINER" --name "sprint4/$RUN/$f" --file "$DIR/$f" --overwrite false --only-show-errors > /dev/null ;;
   gcp) gcloud storage cp "$DIR/$f" "gs://$GCP_BUCKET/sprint4/$RUN/$f" --quiet ;;
  esac || return 1
 done
}
failed=0
for provider in aws azure gcp; do
 if copy_to "$provider"; then
  echo "$(date -u +%FT%TZ) $provider COMPLETE $RUN"
 else
  echo "ERROR: $provider copy failed for $RUN" >&2
  failed=1
 fi
done
if ((failed)); then exit 1; fi
echo "$RUN" > "$HERE/last-successful-run.txt"
echo "SUCCESS: backup copied to all three providers; run $RUN"
