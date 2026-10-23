#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nginx
printf '%s\n' '<h1>Multi cloud Terraform lab</h1><p>Provider AZURE</p>' > /var/www/html/index.html
printf '%s\n' 'healthy azure' > /var/www/html/health
systemctl enable --now nginx
