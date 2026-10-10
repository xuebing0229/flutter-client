# Agent deployment runbook

Target role: deploy the Adventure Guild one-time activation service to a fresh Debian/Ubuntu VPS.

## Safety boundaries

- Do not upload or request the Ed25519 signing private key. It stays on issuer devices only.
- Do not expose port 8765 publicly. The Python API must listen only on 127.0.0.1.
- Do not store account names, passwords, artwork, order data, avatars, or P2P sync data on this server.
- Do not change SSH port or disable the current SSH login during the initial deployment.
- Do not make source-code changes directly on the server. If repository code fails, report the failure instead of inventing a server-only patch.

## Prerequisites

- A DNS hostname such as `license.example.com` whose A record points to the VPS.
- TCP 22, 80 and 443 reachable.
- Root shell.
- Optional email address for Let's Encrypt notices.

## Deployment

Use the public repository and a sparse checkout:

```bash
apt-get update
apt-get install -y git

rm -rf /opt/adventure-license-src
git clone --filter=blob:none --sparse \
  https://github.com/xuebing0229/flutter-client.git \
  /opt/adventure-license-src

cd /opt/adventure-license-src
git sparse-checkout set server/activation_service
cd server/activation_service

chmod +x deploy.sh
LICENSE_DOMAIN='YOUR_DOMAIN' CERTBOT_EMAIL='YOUR_EMAIL' ./deploy.sh
```

If no email is supplied, omit `CERTBOT_EMAIL`; the script can still obtain a certificate.

## Verification

Run all of the following:

```bash
systemctl is-active adventure-license
systemctl is-enabled adventure-license
systemctl is-active nginx
systemctl is-enabled adventure-license-backup.timer

curl -fsS https://YOUR_DOMAIN/health
sqlite3 /var/lib/adventure-license/license.db 'PRAGMA integrity_check;'

ss -lntp
systemctl start adventure-license-backup.service
ls -lah /var/backups/adventure-license/
systemctl list-timers adventure-license-backup.timer --no-pager

certbot renew --dry-run
```

Expected network layout:

- SSH: public 22
- Nginx: public 80/443
- activation API: 127.0.0.1:8765 only

Expected health response contains `"ok":true` and service `adventure-license`.

## Deployment report

Report back:

- hostname and HTTPS URL
- current Git commit deployed
- service / Nginx / backup-timer status
- health-check result
- SQLite integrity-check result
- whether port 8765 is loopback-only
- path of a successfully created backup
- Let's Encrypt renewal dry-run result
- the generated `LICENSE_ADMIN_SETUP_KEY` once, clearly marked as sensitive

Do not print the root password or any unrelated secrets.
