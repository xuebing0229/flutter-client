"""Local-only regression tests for one-code-one-account activation.

Generate an ephemeral signing key and use a temporary SQLite database.
No real activation codes, admin tokens, or customer data are involved.
"""

import base64
import json
import subprocess
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from http.server import ThreadingHTTPServer
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from server.activation_service import app as service


def _url_b64(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


class ActivationServiceTests(unittest.TestCase):
    def setUp(self):
        self._temp = tempfile.TemporaryDirectory(prefix="guild-license-test-")
        self._previous_db = service.DB_PATH
        self._previous_key = service.PUBLIC_KEY_B64URL
        service.DB_PATH = str(Path(self._temp.name) / "licenses.sqlite3")
        self._signer = Ed25519PrivateKey.generate()
        public_bytes = self._signer.public_key().public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw,
        )
        service.PUBLIC_KEY_B64URL = _url_b64(public_bytes)
        service.init_db()

        conn = service.connect_db()
        try:
            conn.execute(
                """INSERT INTO admins (name, token_hash, created_at)
                   VALUES (?, ?, ?)""",
                ("test-admin", service.token_hash("test-admin-token"), service.utc_now()),
            )
            conn.commit()
        finally:
            conn.close()

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), service.Handler)
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()
        self.base_url = f"http://127.0.0.1:{self.httpd.server_port}"

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join(timeout=5)
        service.DB_PATH = self._previous_db
        service.PUBLIC_KEY_B64URL = self._previous_key
        self._temp.cleanup()

    def _new_code(self, account_id="account_from_signed_code"):
        conn = service.connect_db()
        try:
            cursor = conn.execute(
                """INSERT INTO licenses (
                   account_id, generated_by_admin_id,
                   generated_by_name, created_at, note
                ) VALUES (?, 1, 'test-admin', ?, '')""",
                (account_id, service.utc_now()),
            )
            serial = str(cursor.lastrowid).zfill(6)
            payload = json.dumps(
                {"v": 2, "a": account_id, "s": serial},
                separators=(",", ":"),
            ).encode("utf-8")
            code = f"AW2.{_url_b64(payload)}.{_url_b64(self._signer.sign(payload))}"
            conn.execute(
                "UPDATE licenses SET activation_code = ?, committed_at = ? WHERE account_id = ?",
                (code, service.utc_now(), account_id),
            )
            conn.commit()
            return code
        finally:
            conn.close()

    def _redeem(self, code, claim_id):
        payload = json.dumps(
            {"activationCode": code, "claimId": claim_id}
        ).encode("utf-8")
        request = urllib.request.Request(
            f"{self.base_url}/v1/activate",
            data=payload,
            method="POST",
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as error:
            with error:
                return error.code, json.load(error)

    def _redemption(self, account_id="account_from_signed_code"):
        conn = service.connect_db()
        try:
            return conn.execute(
                "SELECT redeemed_at, redemption_claim_id FROM licenses WHERE account_id = ?",
                (account_id,),
            ).fetchone()
        finally:
            conn.close()

    def test_first_activation_consumes_code_and_is_retryable_only_by_same_claim(self):
        code = self._new_code()
        claim_a = "claim-a-12345678901234567890"
        claim_b = "claim-b-12345678901234567890"

        first_status, first = self._redeem(code, claim_a)
        retry_status, retry = self._redeem(code, claim_a)
        rejected_status, rejected = self._redeem(code, claim_b)

        self.assertEqual(first_status, 200)
        self.assertFalse(first["idempotent"])
        self.assertEqual(retry_status, 200)
        self.assertTrue(retry["idempotent"])
        self.assertEqual(first["redeemedAt"], retry["redeemedAt"])
        self.assertEqual(rejected_status, 409)
        self.assertEqual(rejected["error"], "already_redeemed")
        self.assertEqual(self._redemption()["redemption_claim_id"], claim_a)

    def test_concurrent_first_claims_never_create_two_registrations(self):
        code = self._new_code()
        gate = threading.Barrier(2)

        def attempt(claim):
            gate.wait(timeout=5)
            return self._redeem(code, claim)

        with ThreadPoolExecutor(max_workers=2) as executor:
            a = executor.submit(attempt, "claim-a-12345678901234567890")
            b = executor.submit(attempt, "claim-b-12345678901234567890")
            responses = [a.result(timeout=10), b.result(timeout=10)]

        self.assertEqual(sorted(status for status, _ in responses), [200, 409])
        self.assertIsNotNone(self._redemption()["redeemed_at"])

    def test_invalid_signature_does_not_redeem_record(self):
        code = self._new_code()
        malformed = code.rsplit(".", 1)[0] + ".AAAA"
        status, payload = self._redeem(
            malformed, "claim-a-12345678901234567890"
        )
        self.assertEqual(status, 400)
        self.assertEqual(payload["error"], "invalid_code")
        self.assertIsNone(self._redemption()["redeemed_at"])

    def _list_licenses(self, query="", token="test-admin-token"):
        request = urllib.request.Request(
            f"{self.base_url}/v1/licenses?{query}",
            headers={"Authorization": f"Bearer {token}"},
        )
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as error:
            with error:
                return error.code, json.load(error)

    def test_keyset_pages_cover_more_than_500_licenses_without_duplicates(self):
        # Keep this fast: ledger history only needs a stored signed-code
        # marker, not 1,205 expensive signatures for the query test.
        conn = service.connect_db()
        try:
            conn.executemany(
                """INSERT INTO licenses (
                    account_id, activation_code, note, generated_by_admin_id,
                    generated_by_name, created_at
                ) VALUES (?, ?, '', 1, 'test-admin', ?)""",
                [
                    (f"record-{i:05d}", f"code-{i:05d}", service.utc_now())
                    for i in range(1205)
                ],
            )
            conn.execute(
                """UPDATE licenses SET voided_at = ?
                WHERE account_id = 'record-00007'""",
                (service.utc_now(),),
            )
            conn.commit()
        finally:
            conn.close()

        records = []
        before = None
        pages = 0
        while True:
            query = "limit=500"
            if before is not None:
                query += f"&beforeId={before}"
            status, response = self._list_licenses(query)
            self.assertEqual(status, 200)
            batch = response["licenses"]
            self.assertLessEqual(len(batch), 500)
            records.extend(batch)
            pages += 1
            before_next = response["nextBeforeId"]
            if before_next is None:
                break
            self.assertEqual(before_next, int(batch[-1]["serial"]))
            if before is not None:
                self.assertLess(before_next, before)
            before = before_next
            # New license issued mid-refresh must not shift earlier pages.
            if pages == 1:
                self._new_code("inserted_after_first_page")
        self.assertEqual(pages, 3)
        self.assertEqual(len(records), 1204)
        self.assertEqual(len({r["serial"] for r in records}), 1204)
        self.assertNotIn("record-00007", {r["accountId"] for r in records})
        self.assertNotIn(
            "inserted_after_first_page", {r["accountId"] for r in records}
        )
        status, fresh = self._list_licenses("limit=1")
        self.assertEqual(status, 200)
        self.assertEqual(
            fresh["licenses"][0]["accountId"], "inserted_after_first_page"
        )

    def test_deployment_rate_limits_are_scoped_to_sensitive_endpoints(self):
        folder = Path(__file__).parent
        script = (folder / "deploy.sh").read_text(encoding="utf-8")
        example = (folder / "nginx.conf.example").read_text(encoding="utf-8")
        zones = (folder / "nginx.rate-limits.conf.example").read_text(
            encoding="utf-8"
        )
        subprocess.run(["bash", "-n", str(folder / "deploy.sh")], check=True)
        for text in (script, example):
            self.assertIn("location = /v1/admin/register", text)
            self.assertIn("location = /v1/activate", text)
            self.assertIn("limit_req_status 429;", text)
            self.assertIn("zone=guild_admin_enroll burst=3 nodelay;", text)
            self.assertIn("zone=guild_activation burst=15 nodelay;", text)
        self.assertIn(
            "limit_req_zone $binary_remote_addr zone=guild_admin_enroll",
            zones,
        )
        self.assertIn(
            "limit_req_zone $binary_remote_addr zone=guild_activation",
            zones,
        )

    def test_pagination_rejects_invalid_cursors_and_requires_admin(self):
        for query in ("limit=0", "limit=501", "limit=nonsense",
                      "beforeId=0", "beforeId=-5", "beforeId=bad"):
            status, result = self._list_licenses(query)
            self.assertEqual(status, 400, msg=query)
            self.assertEqual(result["error"], "invalid_pagination")
        status, result = self._list_licenses("limit=2", token="invalid")
        self.assertEqual(status, 401)
        self.assertEqual(result["error"], "unauthorized")

    def test_signed_but_unregistered_code_is_rejected(self):
        code = self._new_code("registered-account")
        parts = code.split(".")
        payload = json.dumps(
            {"v": 2, "a": "unregistered-account", "s": "000999"},
            separators=(",", ":"),
        ).encode("utf-8")
        unregistered_code = (
            f"AW2.{_url_b64(payload)}.{_url_b64(self._signer.sign(payload))}"
        )
        self.assertNotEqual(code, unregistered_code)
        status, response = self._redeem(
            unregistered_code, "claim-a-12345678901234567890"
        )
        self.assertEqual(status, 400)
        self.assertEqual(response["error"], "invalid_code")
        self.assertIsNone(self._redemption("registered-account")["redeemed_at"])


if __name__ == "__main__":
    unittest.main()
