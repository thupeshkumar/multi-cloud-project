#!/usr/bin/env bash
set -euo pipefail
: "${KNOWN_HOSTS_FILE:?Jenkins must supply the verified known_hosts file}"
REVISION="$(git rev-parse --short=12 HEAD)"
[[ "$REVISION" =~ ^[a-f0-9]{7,40}$ ]]
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$KNOWN_HOSTS_FILE" -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=3)
mkdir -p deployment-evidence
date -u +%FT%TZ > deployment-evidence/started.txt
printf '%s\n' "$REVISION" > deployment-evidence/revision.txt
while read -r cloud user ip extra; do
  [[ -z "$cloud" || "$cloud" == \#* ]] && continue
  [[ -z "$extra" && "$cloud" =~ ^(aws|azure|gcp)$ && "$user" =~ ^[a-z_][a-z0-9_-]*$ && "$ip" =~ ^[0-9.]+$ ]] || {
    echo "Invalid target configuration" >&2; exit 1;
  }
  host="$user@$ip"
  echo "Preflight $cloud"
  ssh -n "${SSH_OPTS[@]}" "$host" 'sudo -n nginx -t'
done < jenkins/targets.txt

while read -r cloud user ip extra; do
  [[ -z "$cloud" || "$cloud" == \#* ]] && continue
  host="$user@$ip"
  mkdir -p "deployment-evidence/$cloud"
  sed -e "s/{{CLOUD}}/$cloud/g" -e "s/{{REVISION}}/$REVISION/g" app/index.html.template > "deployment-evidence/$cloud/index.html"
  printf 'healthy %s\n' "$cloud" > "deployment-evidence/$cloud/health"
  STAGING="$(ssh -n "${SSH_OPTS[@]}" "$host" 'umask 077; mktemp -d /tmp/multicloud-jenkins.XXXXXXXX')"
  [[ "$STAGING" =~ ^/tmp/multicloud-jenkins\.[a-zA-Z0-9]+$ ]] || { echo 'Unexpected staging path' >&2; exit 1; }
  scp "${SSH_OPTS[@]}" "deployment-evidence/$cloud/index.html" "deployment-evidence/$cloud/health" "$host:$STAGING/"
  ssh -n "${SSH_OPTS[@]}" "$host" \
    "set -e; sudo -n install -m 0644 '\$STAGING/index.html' '/var/www/html/.index-\$REVISION.html'; sudo -n install -m 0644 '\$STAGING/health' '/var/www/html/.health-\$REVISION'; sudo -n mv '/var/www/html/.index-\$REVISION.html' /var/www/html/index.html; sudo -n mv '/var/www/html/.health-\$REVISION' /var/www/html/health"
  # Verify the actual content on the public origin, independently of shared DNS.
  curl --fail --silent --show-error --max-time 15 "http://$ip/health" > "deployment-evidence/$cloud/actual-health"
  cmp "deployment-evidence/$cloud/health" "deployment-evidence/$cloud/actual-health"
  curl --fail --silent --show-error --max-time 15 "http://$ip/" > "deployment-evidence/$cloud/actual-index.html"
  cmp "deployment-evidence/$cloud/index.html" "deployment-evidence/$cloud/actual-index.html"
  echo "$(date -u +%FT%TZ) $cloud verified $ip revision $REVISION" | tee -a deployment-evidence/result.txt
  # Staging and archived evidence remain for inspection; no automatic data deletion.
done < jenkins/targets.txt