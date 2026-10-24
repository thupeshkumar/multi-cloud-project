#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/common.sh"
[[ $# == 2 ]] || { echo "Usage: bash restore.sh aws|azure|gcp RUN_ID"; exit 1; }
STORE="$1"; RUN="$2"
[[ "$STORE" =~ ^(aws|azure|gcp)$ && "$RUN" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9]+$ ]] || exit 1
TAG="$(date -u +%Y%m%dT%H%M%SZ)_$$"
DIR="$HERE/recovered/$RUN-$TAG"
mkdir -p "$DIR"
SECONDS=0
date -u +%FT%TZ > "$DIR/restore-started.txt"
download() {
 local f="$1"
 case "$STORE" in
 aws) aws s3 cp "s3://$AWS_BUCKET/sprint4/$RUN/$f" "$DIR/$f" --only-show-errors ;;
 azure) az storage blob download --auth-mode login --account-name "$AZURE_STORAGE_ACCOUNT" --container-name "$AZURE_CONTAINER" --name "sprint4/$RUN/$f" --file "$DIR/$f" --only-show-errors > /dev/null ;;
 gcp) gcloud storage cp "gs://$GCP_BUCKET/sprint4/$RUN/$f" "$DIR/$f" --quiet ;;
 esac
}
# Require a completion marker before downloading or restoring this generation.
download COMPLETE
for f in projectdb.dump expected.csv backup-started.txt archive-list.txt SHA256SUMS; do download "$f"; done
(cd "$DIR"; sha256sum -c SHA256SUMS)
DB="restore_${TAG,,}"
REMOTE="dr-restore-$TAG"
ssh "${SSH[@]}" "$TARGET_HOST" \
 "umask 077; mkdir '$REMOTE'; sudo -n docker exec '$TARGET_CONTAINER' pg_isready -U '$TARGET_USER' -d postgres"
scp "${SSH[@]}" "$DIR/projectdb.dump" "$TARGET_HOST:$REMOTE/projectdb.dump"
ssh "${SSH[@]}" "$TARGET_HOST" \
 "sudo -n docker exec '$TARGET_CONTAINER' createdb -U '$TARGET_USER' -T template0 '$DB'"
ssh "${SSH[@]}" "$TARGET_HOST" \
 "sudo -n docker exec -i '$TARGET_CONTAINER' pg_restore --exit-on-error --single-transaction --no-owner --no-acl -U '$TARGET_USER' -d '$DB' < '$REMOTE/projectdb.dump'"
ssh "${SSH[@]}" "$TARGET_HOST" \
 "sudo -n docker exec '$TARGET_CONTAINER' psql -X -q -v ON_ERROR_STOP=1 -U '$TARGET_USER' -d '$DB' -c 'COPY (SELECT id,message FROM public.dr_evidence ORDER BY id) TO STDOUT WITH CSV HEADER'" \
 > "$DIR/actual.csv"
cmp "$DIR/expected.csv" "$DIR/actual.csv"
{
 echo "PASS: SHA256 archive integrity and ordered dr_evidence rows match"
 echo "Backup store: $STORE"
 echo "Run: $RUN"
 echo "Target: $TARGET_HOST"
 echo "Database: $DB"
 echo "Restore workflow seconds: $SECONDS"
 echo "Verification finished UTC: $(date -u +%FT%TZ)"
} | tee "$DIR/result.txt"
echo "Retained remote staging directory: ~/$REMOTE"
echo "This verifies database restoration, not application traffic cutover."
