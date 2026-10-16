#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

DOMAIN="${RELEASE_DOMAIN:-license.apixb.top}"
DEPLOY_USER="${RELEASE_DEPLOY_USER:-adventure-release}"
PUBLIC_KEY="${RELEASE_DEPLOY_PUBLIC_KEY:-}"
NGINX_SITE="${RELEASE_NGINX_SITE:-/etc/nginx/sites-available/adventure-license}"
RELEASE_ROOT="${RELEASE_ROOT:-/srv/adventure-releases}"

if [[ -z "$PUBLIC_KEY" ]]; then
  echo "Set RELEASE_DEPLOY_PUBLIC_KEY to the CI deploy public key." >&2
  exit 2
fi
if [[ ! -f "$NGINX_SITE" ]]; then
  echo "Nginx site not found: $NGINX_SITE" >&2
  exit 3
fi

id "$DEPLOY_USER" >/dev/null 2>&1 ||   useradd --create-home --shell /bin/bash "$DEPLOY_USER"

install -d -o "$DEPLOY_USER" -g "$DEPLOY_USER" -m 0755 "$RELEASE_ROOT"
install -d -o "$DEPLOY_USER" -g "$DEPLOY_USER" -m 0755 "$RELEASE_ROOT/internal"

HOME_DIR="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
install -d -o "$DEPLOY_USER" -g "$DEPLOY_USER" -m 0700 "$HOME_DIR/.ssh"
printf '%s\n' "$PUBLIC_KEY" > "$HOME_DIR/.ssh/authorized_keys"
chown "$DEPLOY_USER:$DEPLOY_USER" "$HOME_DIR/.ssh/authorized_keys"
chmod 0600 "$HOME_DIR/.ssh/authorized_keys"

python3 - "$NGINX_SITE" "$RELEASE_ROOT" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
root = sys.argv[2].rstrip("/")
text = path.read_text()
marker = "    location ^~ /releases/ {"
if marker not in text:
    proxy_marker = "    location / {"
    block = f"""    location ^~ /releases/ {{
        alias {root}/;
        autoindex off;
        limit_except GET HEAD {{ deny all; }}
        add_header Cache-Control "no-cache";
    }}

"""
    if proxy_marker not in text:
        raise SystemExit("Could not find the existing location / block.")
    text = text.replace(proxy_marker, block + proxy_marker, 1)
    path.write_text(text)
PY

nginx -t
systemctl reload nginx

echo "Prepared release site:"
echo "  https://$DOMAIN/releases/"
echo "  release root: $RELEASE_ROOT"
echo "  deploy user: $DEPLOY_USER"
