# Adventure License — Cloudflare Worker + D1

This directory is the Cloudflare replacement for `server/activation_service/app.py`.

The public HTTP contract is intentionally kept compatible with the current Android/Windows clients and the private issuer:

- `GET /health`
- `POST /v1/admin/register`
- `GET /v1/admin/me`
- `PATCH /v1/admin/me`
- `GET /v1/licenses`
- `POST /v1/licenses/import`
- `POST /v1/licenses/reserve`
- `POST /v1/licenses/:accountId/commit`
- `PATCH /v1/licenses/:accountId/note`
- `POST /v1/licenses/:accountId/sold`
- `DELETE /v1/licenses/:accountId`
- `POST /v1/activate`

The AW1/AW2 Ed25519 public key and validation rules are unchanged. The private signing key remains only on issuer devices and is never uploaded to Cloudflare.

## Safety rule: do not bind the production hostname yet

Do **not** attach `license.apixb.top` until the D1 import and workers.dev staging checks pass.

Current production builds use that exact hostname, and the Android direct-network fallback explicitly allow-lists it. The final migration should therefore change only the origin behind the same hostname, with no client rebuild.

## One-time Cloudflare setup

From this directory, authenticated to the correct Cloudflare account:

```bash
npm install
npx wrangler d1 create adventure-license --location=apac
```

Copy the returned D1 UUID into `wrangler.jsonc` as `database_id`.

Set the administrator enrollment secret to the **same value** currently configured on the VPS:

```bash
npx wrangler secret put LICENSE_ADMIN_SETUP_KEY
```

Do not rotate this secret as part of the migration unless issuer enrollment is intentionally being reset. Existing issuer administrator tokens continue to work because the `admins` table, including token hashes, is migrated intact.

## Final database copy from the VPS

Stop the old service before the final copy so there are no writes during migration:

```bash
sudo systemctl stop adventure-license
sudo sqlite3 /var/lib/adventure-license/license.db ".backup '/tmp/license-final.sqlite'"
sqlite3 /tmp/license-final.sqlite .dump > /tmp/license-final.raw.sql
python3 scripts/prepare_d1_dump.py /tmp/license-final.raw.sql /tmp/license-final.d1.sql
```

Import into D1:

```bash
npx wrangler d1 execute adventure-license --remote --file=/tmp/license-final.d1.sql
```

Verify row counts:

```bash
npx wrangler d1 execute adventure-license --remote --command \
  "SELECT 'admins' AS t, COUNT(*) AS n FROM admins UNION ALL SELECT 'licenses', COUNT(*) FROM licenses UNION ALL SELECT 'audit_log', COUNT(*) FROM audit_log;"
```

## Staging verification

First deploy only to the generated `workers.dev` hostname:

```bash
npx wrangler deploy
```

Before production cutover verify:

1. `GET /health` returns `service=adventure-license`, version 1.
2. An existing issuer token can call `GET /v1/admin/me`.
3. `GET /v1/licenses` agrees with the old server data.
4. A fresh test code completes reserve -> AW2 local signing -> commit -> sold -> activate.
5. Repeating activation with the same `claimId` returns `idempotent=true`.
6. The same code with a different `claimId` returns `409 already_redeemed`.
7. A stale `X-License-Revision` returns `409 stale_record`.

If staging fails, restart the VPS service and do not touch the production hostname.

## Production cutover

After staging passes, attach `license.apixb.top` to this Worker as a Cloudflare **Custom Domain**.

Do not change `ACTIVATION_API_BASE_URL` in Flutter builds. Keeping the hostname means existing Android, Windows and issuer builds continue working without a rebuild.

After cutover, repeat the smoke tests against `https://license.apixb.top`. Keep the VPS stopped but intact for a rollback window. Once production is confirmed healthy, retire the old systemd service, Nginx vhost, SQLite database and backup timer.

## Concurrency compatibility

The VPS implementation serializes writes with SQLite `BEGIN IMMEDIATE`.

D1 does not expose that application-side locking model. First redemption therefore uses an atomic conditional update:

```sql
UPDATE licenses
SET redeemed_at = ?, redemption_claim_id = ?, revision = revision + 1
WHERE account_id = ?
  AND redeemed_at IS NULL
  AND voided_at IS NULL
  AND activation_code = ?;
```

Only one competing first-redemption request can change the row. A losing request re-reads the record: the same `claimId` is treated as an idempotent retry, while a different one returns `already_redeemed`.

Revision-guarded administrator edits also include the expected revision in the final `UPDATE ... WHERE` clause, preventing a stale editor from overwriting a newer value between read and write.
