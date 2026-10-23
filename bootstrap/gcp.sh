#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nginx
printf '%s\n' '<h1>Multi cloud Terraform lab</h1><p>Provider GCP</p>' > /var/www/html/index.html
printf '%s\n' 'healthy gcp' > /var/www/html/health
systemctl enable --now nginx
