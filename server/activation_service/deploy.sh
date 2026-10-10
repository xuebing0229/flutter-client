#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

DOMAIN="${LICENSE_DOMAIN:-}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"

if [[ -z "$DOMAIN" ]]; then
  echo "Set LICENSE_DOMAIN to the activation-service hostname, for example:" >&2
  echo "  LICENSE_DOMAIN=license.example.com CERTBOT_EMAIL=you@example.com ./deploy.sh" >&2
  exit 2
fi

if [[ ! "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "Invalid LICENSE_DOMAIN: $DOMAIN" >&2
  exit 2
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

chmod +x install.sh backup.sh smoke_test.sh
./install.sh

# Limits live in the nginx http context (conf.d), not inside the server
# block. Registration is especially sensitive to setup-key guessing.
# Keep generous activation bursts for shared carrier NATs and retrying users.
cat >/etc/nginx/conf.d/adventure-license-rates.conf <<'RATES'
limit_req_zone $binary_remote_addr zone=guild_admin_enroll:10m rate=3r/m;
limit_req_zone $binary_remote_addr zone=guild_activation:10m rate=30r/m;
RATES

cat >/etc/nginx/sites-available/adventure-license <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    client_max_body_size 1m;

    limit_req_status 429;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_connect_timeout 5s;
    proxy_read_timeout 15s;

    location = /v1/admin/register {
        limit_req zone=guild_admin_enroll burst=3 nodelay;
        proxy_pass http://127.0.0.1:8765;
    }

    location = /v1/activate {
        limit_req zone=guild_activation burst=15 nodelay;
        proxy_pass http://127.0.0.1:8765;
    }

    location / {
        proxy_pass http://127.0.0.1:8765;
    }
}
EOF

ln -sfn /etc/nginx/sites-available/adventure-license   /etc/nginx/sites-enabled/adventure-license
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl enable --now nginx
systemctl reload nginx

echo
echo "Checking HTTP before certificate issuance..."
curl --fail --show-error --silent   --connect-timeout 8   --max-time 15   "http://$DOMAIN/health"
echo

certbot_args=(
  --nginx
  -d "$DOMAIN"
  --redirect
  --non-interactive
  --agree-tos
)
if [[ -n "$CERTBOT_EMAIL" ]]; then
  certbot_args+=(--email "$CERTBOT_EMAIL")
else
  certbot_args+=(--register-unsafely-without-email)
fi

certbot "${certbot_args[@]}"

systemctl start adventure-license-backup.service

echo
echo "Checking HTTPS..."
curl --fail --show-error --silent   --connect-timeout 8   --max-time 15   "https://$DOMAIN/health"
echo

echo
echo "Deployment complete."
echo "API: https://$DOMAIN"
echo "Database: /var/lib/adventure-license/license.db"
echo "Backups: /var/backups/adventure-license"
echo "Service env: /etc/adventure-license/service.env"
echo
echo "Keep LICENSE_ADMIN_SETUP_KEY private. It is used only to enroll issuer administrators."
