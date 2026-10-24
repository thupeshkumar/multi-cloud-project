#!/usr/bin/env bash
set -euo pipefail
umask 077
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/dr.env"
SSH=(-i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10)
for key in SOURCE_HOST TARGET_HOST; do
  [[ "${!key}" =~ ^[a-zA-Z0-9_-]+@[a-zA-Z0-9.-]+$ ]] || exit 1
done
for key in SOURCE_CONTAINER SOURCE_USER SOURCE_DB TARGET_CONTAINER TARGET_USER; do
  [[ "${!key}" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] || exit 1
done
for key in AWS_BUCKET AZURE_STORAGE_ACCOUNT AZURE_CONTAINER GCP_BUCKET; do
  [[ "${!key}" != REPLACE && "${!key}" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || {
    echo "Configure $key in dr.env" >&2; exit 1;
  }
done
