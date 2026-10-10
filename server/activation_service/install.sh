#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

apt-get update
apt-get install -y python3 python3-cryptography sqlite3 nginx certbot python3-certbot-nginx curl

id adventure-license >/dev/null 2>&1 || \
  useradd --system --home /nonexistent --shell /usr/sbin/nologin adventure-license

install -d -o root -g root -m 0755 /opt/adventure-license
install -d -o adventure-license -g adventure-license -m 0750 /var/lib/adventure-license
install -d -o root -g adventure-license -m 0750 /etc/adventure-license

python3 -m py_compile app.py

install -o root -g root -m 0755 app.py /opt/adventure-license/app.py
install -o root -g root -m 0755 backup.sh /opt/adventure-license/backup.sh
install -o root -g root -m 0755 smoke_test.sh /opt/adventure-license/smoke_test.sh
install -o root -g root -m 0644 adventure-license.service /etc/systemd/system/adventure-license.service
install -o root -g root -m 0644 adventure-license-backup.service /etc/systemd/system/adventure-license-backup.service
install -o root -g root -m 0644 adventure-license-backup.timer /etc/systemd/system/adventure-license-backup.timer

if [[ ! -f /etc/adventure-license/service.env ]]; then
  setup_key="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(36))
PY
)"
  cat >/etc/adventure-license/service.env <<EOF
LICENSE_BIND_HOST=127.0.0.1
LICENSE_BIND_PORT=8765
LICENSE_DB_PATH=/var/lib/adventure-license/license.db
LICENSE_ADMIN_SETUP_KEY=${setup_key}
EOF
  chown root:adventure-license /etc/adventure-license/service.env
  chmod 0640 /etc/adventure-license/service.env
  echo
  echo "Created /etc/adventure-license/service.env"
  echo "Save the admin setup key somewhere safe:"
  echo "${setup_key}"
  echo
fi

systemctl daemon-reload
systemctl enable --now adventure-license
systemctl enable --now adventure-license-backup.timer
systemctl --no-pager --full status adventure-license || true

echo
echo "Local health check:"
LICENSE_DB_PATH=/var/lib/adventure-license/license.db /opt/adventure-license/smoke_test.sh http://127.0.0.1:8765
echo
echo "Backup timer:"
systemctl list-timers adventure-license-backup.timer --no-pager
