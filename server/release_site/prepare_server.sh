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

# Do not silently claim CI SSH is ready when sshd only permits password auth.
# The exact server SSH policy may be managed elsewhere, so this script verifies
# the effective per-user configuration instead of blindly rewriting global SSH.
SSHD_EFFECTIVE="$(sshd -T -C "user=$DEPLOY_USER,host=$DOMAIN,addr=127.0.0.1" 2>/dev/null || true)"
if ! grep -q '^pubkeyauthentication yesfrom pathlib import Path
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
        # Android may temporarily stop reading the socket while the app is in
        # the background. Keep long APK transfers alive instead of dropping
        # them at nginx's default 60s send timeout.
        send_timeout 30m;
        sendfile on;
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
 <<<"$SSHD_EFFECTIVE"; then
  echo "ERROR: sshd does not currently allow public-key authentication for $DEPLOY_USER." >&2
  echo "Fix the effective sshd policy for this user, run 'sshd -t', reload ssh, then rerun this script." >&2
  exit 4
fi
if ! grep -q '^authorizedkeysfile .*\.ssh/authorized_keys' <<<"$SSHD_EFFECTIVE"; then
  echo "WARNING: sshd AuthorizedKeysFile for $DEPLOY_USER is nonstandard:" >&2
  grep '^authorizedkeysfile ' <<<"$SSHD_EFFECTIVE" >&2 || true
fi

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
