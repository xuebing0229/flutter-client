#!/usr/bin/env python3
import base64
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import threading
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

PUBLIC_KEY_B64URL = "y4fObOqoJ0gXSs8oyp9av0JiKpYj5HIA-0_PxTZ30eQ"
DB_PATH = os.environ.get("LICENSE_DB_PATH", "/var/lib/adventure-license/license.db")
BIND_HOST = os.environ.get("LICENSE_BIND_HOST", "127.0.0.1")
BIND_PORT = int(os.environ.get("LICENSE_BIND_PORT", "8765"))
SETUP_KEY = os.environ.get("LICENSE_ADMIN_SETUP_KEY", "").strip()
API_VERSION = 1

_db_lock = threading.Lock()


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def b64url_decode(value: str) -> bytes:
    padding = "=" * ((4 - len(value) % 4) % 4)
    return base64.urlsafe_b64decode(value + padding)


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def connect_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    db = sqlite3.connect(DB_PATH, timeout=15, isolation_level=None)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA foreign_keys=ON")
    db.execute("PRAGMA busy_timeout=15000")
    return db


def init_db():
    with _db_lock, connect_db() as db:
        db.executescript(
            """
            CREATE TABLE IF NOT EXISTS admins (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                token_hash TEXT NOT NULL UNIQUE,
                created_at TEXT NOT NULL,
                disabled_at TEXT
            );

            CREATE TABLE IF NOT EXISTS licenses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                account_id TEXT NOT NULL UNIQUE,
                activation_code TEXT UNIQUE,
                note TEXT NOT NULL DEFAULT '',
                generated_by_admin_id INTEGER NOT NULL,
                generated_by_name TEXT NOT NULL,
                created_at TEXT NOT NULL,
                committed_at TEXT,
                sold_by_admin_id INTEGER,
                sold_by_name TEXT,
                sold_at TEXT,
                redeemed_at TEXT,
                redemption_claim_id TEXT,
                voided_at TEXT,
                FOREIGN KEY(generated_by_admin_id) REFERENCES admins(id),
                FOREIGN KEY(sold_by_admin_id) REFERENCES admins(id)
            );

            CREATE INDEX IF NOT EXISTS idx_licenses_created_at
                ON licenses(created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_licenses_redeemed_at
                ON licenses(redeemed_at);
            CREATE INDEX IF NOT EXISTS idx_licenses_sold_at
                ON licenses(sold_at);

            CREATE TABLE IF NOT EXISTS audit_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at TEXT NOT NULL,
                admin_id INTEGER,
                admin_name TEXT,
                action TEXT NOT NULL,
                account_id TEXT,
                details_json TEXT NOT NULL DEFAULT '{}'
            );
            """
        )


def audit(db, action, *, admin=None, account_id=None, details=None):
    db.execute(
        """
        INSERT INTO audit_log
            (created_at, admin_id, admin_name, action, account_id, details_json)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (
            utc_now(),
            admin["id"] if admin else None,
            admin["name"] if admin else None,
            action,
            account_id,
            json.dumps(details or {}, ensure_ascii=False, separators=(",", ":")),
        ),
    )


def verify_activation_code(code: str):
    parts = code.strip().split(".")
    if len(parts) != 3:
        raise ValueError("激活码格式不正确。")
    expected_version = {"AW1": 1, "AW2": 2}.get(parts[0])
    if expected_version is None:
        raise ValueError("激活码格式不正确。")
    payload_bytes = b64url_decode(parts[1])
    signature = b64url_decode(parts[2])
    public_key = Ed25519PublicKey.from_public_bytes(b64url_decode(PUBLIC_KEY_B64URL))
    public_key.verify(signature, payload_bytes)
    payload = json.loads(payload_bytes.decode("utf-8"))
    if not isinstance(payload, dict) or payload.get("v") != expected_version:
        raise ValueError("激活码版本无效。")
    account_id = payload.get("a")
    serial = payload.get("s")
    if not isinstance(account_id, str) or not account_id:
        raise ValueError("激活码缺少账号身份。")
    if not isinstance(serial, str) or not serial:
        raise ValueError("激活码缺少编号。")
    return account_id, serial


def license_status(row):
    if row["voided_at"]:
        return "void"
    if row["redeemed_at"]:
        return "redeemed"
    if row["sold_at"]:
        return "sold"
    if row["activation_code"]:
        return "unused"
    return "reserved"


def license_json(row):
    return {
        "serial": str(row["id"]).zfill(6),
        "accountId": row["account_id"],
        "activationCode": row["activation_code"],
        "note": row["note"],
        "generatedBy": row["generated_by_name"],
        "createdAt": row["created_at"],
        "soldBy": row["sold_by_name"],
        "soldAt": row["sold_at"],
        "redeemedAt": row["redeemed_at"],
        "status": license_status(row),
    }


class ApiError(Exception):
    def __init__(self, status, message, code="error"):
        super().__init__(message)
        self.status = status
        self.message = message
        self.code = code


class Handler(BaseHTTPRequestHandler):
    server_version = "AdventureLicense/1"

    def log_message(self, fmt, *args):
        print(
            f"{self.address_string()} - [{self.log_date_time_string()}] " + (fmt % args),
            flush=True,
        )

    def _json_body(self):
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0:
            return {}
        if length > 1024 * 1024:
            raise ApiError(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, "请求过大。")
        raw = self.rfile.read(length)
        try:
            value = json.loads(raw.decode("utf-8"))
        except Exception as exc:
            raise ApiError(HTTPStatus.BAD_REQUEST, "JSON 格式无效。") from exc
        if not isinstance(value, dict):
            raise ApiError(HTTPStatus.BAD_REQUEST, "请求内容必须是对象。")
        return value

    def _send(self, status, data):
        body = json.dumps(
            data, ensure_ascii=False, separators=(",", ":")
        ).encode("utf-8")
        self.send_response(int(status))
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _ok(self, data=None, status=HTTPStatus.OK):
        self._send(status, {"ok": True, **(data or {})})

    def _error(self, err):
        self._send(
            err.status,
            {"ok": False, "error": err.code, "message": err.message},
        )

    def _admin(self, db):
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            raise ApiError(HTTPStatus.UNAUTHORIZED, "缺少管理员身份。", "unauthorized")
        token = header[7:].strip()
        if not token:
            raise ApiError(HTTPStatus.UNAUTHORIZED, "缺少管理员身份。", "unauthorized")
        digest = token_hash(token)
        row = db.execute(
            """
            SELECT id, name, created_at
            FROM admins
            WHERE token_hash = ? AND disabled_at IS NULL
            """,
            (digest,),
        ).fetchone()
        if row is None:
            raise ApiError(HTTPStatus.UNAUTHORIZED, "管理员身份无效。", "unauthorized")
        return row

    def do_GET(self):
        try:
            parsed = urlparse(self.path)
            if parsed.path == "/health":
                return self._ok({"service": "adventure-license", "version": API_VERSION})
            if parsed.path == "/v1/admin/me":
                with connect_db() as db:
                    admin = self._admin(db)
                    return self._ok(
                        {"admin": {"id": admin["id"], "name": admin["name"]}}
                    )
            if parsed.path == "/v1/licenses":
                with connect_db() as db:
                    self._admin(db)
                    query = parse_qs(parsed.query)
                    limit = min(max(int(query.get("limit", ["200"])[0]), 1), 500)
                    rows = db.execute(
                        """
                        SELECT * FROM licenses
                        WHERE voided_at IS NULL AND activation_code IS NOT NULL
                        ORDER BY id DESC
                        LIMIT ?
                        """,
                        (limit,),
                    ).fetchall()
                    return self._ok({"licenses": [license_json(row) for row in rows]})
            raise ApiError(HTTPStatus.NOT_FOUND, "接口不存在。", "not_found")
        except ApiError as err:
            self._error(err)
        except Exception as exc:
            print(f"GET error: {exc!r}", flush=True)
            self._error(ApiError(HTTPStatus.INTERNAL_SERVER_ERROR, "服务器内部错误。"))

    def do_POST(self):
        try:
            parsed = urlparse(self.path)
            body = self._json_body()

            if parsed.path == "/v1/admin/register":
                return self._register_admin(body)

            if parsed.path == "/v1/activate":
                return self._activate(body)

            if parsed.path == "/v1/licenses/import":
                return self._import_legacy_license(body)

            if parsed.path == "/v1/licenses/reserve":
                with _db_lock, connect_db() as db:
                    admin = self._admin(db)
                    note = str(body.get("note", "")).strip()[:500]
                    db.execute("BEGIN IMMEDIATE")
                    try:
                        account_id = secrets.token_hex(10)
                        now = utc_now()
                        cur = db.execute(
                            """
                            INSERT INTO licenses
                                (account_id, note, generated_by_admin_id,
                                 generated_by_name, created_at)
                            VALUES (?, ?, ?, ?, ?)
                            """,
                            (account_id, note, admin["id"], admin["name"], now),
                        )
                        serial = str(cur.lastrowid).zfill(6)
                        audit(
                            db,
                            "reserve_license",
                            admin=admin,
                            account_id=account_id,
                            details={"serial": serial},
                        )
                        db.execute("COMMIT")
                    except Exception:
                        db.execute("ROLLBACK")
                        raise
                    return self._ok(
                        {"license": {"serial": serial, "accountId": account_id}},
                        HTTPStatus.CREATED,
                    )

            if parsed.path.startswith("/v1/licenses/") and parsed.path.endswith("/commit"):
                account_id = parsed.path.split("/")[3]
                code = str(body.get("activationCode", "")).strip()
                if not code:
                    raise ApiError(HTTPStatus.BAD_REQUEST, "缺少激活码。")
                if not code.startswith("AW2."):
                    raise ApiError(
                        HTTPStatus.BAD_REQUEST,
                        "新生成的激活码必须使用 AW2 格式。",
                    )
                try:
                    code_account_id, code_serial = verify_activation_code(code)
                except Exception:
                    raise ApiError(HTTPStatus.BAD_REQUEST, "激活码签名无效。")
                if code_account_id != account_id:
                    raise ApiError(HTTPStatus.BAD_REQUEST, "激活码账号身份不匹配。")
                with _db_lock, connect_db() as db:
                    admin = self._admin(db)
                    db.execute("BEGIN IMMEDIATE")
                    try:
                        row = db.execute(
                            "SELECT * FROM licenses WHERE account_id = ?",
                            (account_id,),
                        ).fetchone()
                        if row is None:
                            raise ApiError(HTTPStatus.NOT_FOUND, "预留记录不存在。")
                        expected_serial = str(row["id"]).zfill(6)
                        if code_serial != expected_serial:
                            raise ApiError(HTTPStatus.BAD_REQUEST, "激活码编号不匹配。")
                        if row["voided_at"]:
                            raise ApiError(HTTPStatus.CONFLICT, "这条记录已经作废。")
                        if row["activation_code"] and row["activation_code"] != code:
                            raise ApiError(HTTPStatus.CONFLICT, "这条记录已经提交过其他激活码。")
                        if not row["activation_code"]:
                            db.execute(
                                """
                                UPDATE licenses
                                SET activation_code = ?, committed_at = ?
                                WHERE account_id = ?
                                """,
                                (code, utc_now(), account_id),
                            )
                            audit(db, "commit_license", admin=admin, account_id=account_id)
                        db.execute("COMMIT")
                    except Exception:
                        db.execute("ROLLBACK")
                        raise
                    row = db.execute(
                        "SELECT * FROM licenses WHERE account_id = ?",
                        (account_id,),
                    ).fetchone()
                    return self._ok({"license": license_json(row)})

            if parsed.path.startswith("/v1/licenses/") and parsed.path.endswith("/sold"):
                account_id = parsed.path.split("/")[3]
                sold = body.get("sold")
                if not isinstance(sold, bool):
                    raise ApiError(HTTPStatus.BAD_REQUEST, "sold 必须是布尔值。")
                with _db_lock, connect_db() as db:
                    admin = self._admin(db)
                    db.execute("BEGIN IMMEDIATE")
                    try:
                        row = db.execute(
                            "SELECT * FROM licenses WHERE account_id = ?",
                            (account_id,),
                        ).fetchone()
                        if row is None or row["voided_at"]:
                            raise ApiError(HTTPStatus.NOT_FOUND, "激活码记录不存在。")
                        if not row["activation_code"]:
                            raise ApiError(HTTPStatus.CONFLICT, "激活码尚未生成完成。")
                        if sold:
                            if row["activation_code"].startswith("AW1."):
                                raise ApiError(
                                    HTTPStatus.CONFLICT,
                                    "旧版 AW1 激活码不能用于新的销售，请生成新的 AW2 激活码。",
                                    "legacy_code_not_sellable",
                                )
                            db.execute(
                                """
                                UPDATE licenses
                                SET sold_by_admin_id = ?, sold_by_name = ?, sold_at = ?
                                WHERE account_id = ?
                                """,
                                (admin["id"], admin["name"], utc_now(), account_id),
                            )
                            action = "mark_sold"
                        else:
                            db.execute(
                                """
                                UPDATE licenses
                                SET sold_by_admin_id = NULL, sold_by_name = NULL,
                                    sold_at = NULL
                                WHERE account_id = ?
                                """,
                                (account_id,),
                            )
                            action = "mark_unsold"
                        audit(db, action, admin=admin, account_id=account_id)
                        db.execute("COMMIT")
                    except Exception:
                        db.execute("ROLLBACK")
                        raise
                    row = db.execute(
                        "SELECT * FROM licenses WHERE account_id = ?",
                        (account_id,),
                    ).fetchone()
                    return self._ok({"license": license_json(row)})

            raise ApiError(HTTPStatus.NOT_FOUND, "接口不存在。", "not_found")
        except ApiError as err:
            self._error(err)
        except Exception as exc:
            print(f"POST error: {exc!r}", flush=True)
            self._error(ApiError(HTTPStatus.INTERNAL_SERVER_ERROR, "服务器内部错误。"))

    def do_PATCH(self):
        try:
            parsed = urlparse(self.path)
            body = self._json_body()

            if parsed.path == "/v1/admin/me":
                name = str(body.get("name", "")).strip()
                if not name or len(name) > 24:
                    raise ApiError(
                        HTTPStatus.BAD_REQUEST,
                        "管理昵称需要在 1–24 个字符之间。",
                    )
                with _db_lock, connect_db() as db:
                    admin = self._admin(db)
                    db.execute("BEGIN IMMEDIATE")
                    try:
                        db.execute(
                            "UPDATE admins SET name = ? WHERE id = ?",
                            (name, admin["id"]),
                        )
                        updated = {"id": admin["id"], "name": name}
                        audit(db, "rename_admin", admin=updated)
                        db.execute("COMMIT")
                    except Exception:
                        db.execute("ROLLBACK")
                        raise
                    return self._ok({"admin": updated})

            if parsed.path.startswith("/v1/licenses/") and parsed.path.endswith("/note"):
                account_id = parsed.path.split("/")[3]
                note = str(body.get("note", "")).strip()[:500]
                with _db_lock, connect_db() as db:
                    admin = self._admin(db)
                    db.execute("BEGIN IMMEDIATE")
                    try:
                        row = db.execute(
                            "SELECT * FROM licenses WHERE account_id = ?",
                            (account_id,),
                        ).fetchone()
                        if row is None or row["voided_at"]:
                            raise ApiError(HTTPStatus.NOT_FOUND, "激活码记录不存在。")
                        db.execute(
                            "UPDATE licenses SET note = ? WHERE account_id = ?",
                            (note, account_id),
                        )
                        audit(db, "update_note", admin=admin, account_id=account_id)
                        db.execute("COMMIT")
                    except Exception:
                        db.execute("ROLLBACK")
                        raise
                    row = db.execute(
                        "SELECT * FROM licenses WHERE account_id = ?",
                        (account_id,),
                    ).fetchone()
                    return self._ok({"license": license_json(row)})
            raise ApiError(HTTPStatus.NOT_FOUND, "接口不存在。", "not_found")
        except ApiError as err:
            self._error(err)
        except Exception as exc:
            print(f"PATCH error: {exc!r}", flush=True)
            self._error(ApiError(HTTPStatus.INTERNAL_SERVER_ERROR, "服务器内部错误。"))

    def do_DELETE(self):
        try:
            parsed = urlparse(self.path)
            if parsed.path.startswith("/v1/licenses/"):
                account_id = parsed.path.split("/")[3]
                with _db_lock, connect_db() as db:
                    admin = self._admin(db)
                    db.execute("BEGIN IMMEDIATE")
                    try:
                        row = db.execute(
                            "SELECT * FROM licenses WHERE account_id = ?",
                            (account_id,),
                        ).fetchone()
                        if row is None or row["voided_at"]:
                            raise ApiError(HTTPStatus.NOT_FOUND, "激活码记录不存在。")
                        if row["redeemed_at"]:
                            raise ApiError(
                                HTTPStatus.CONFLICT,
                                "已核销的激活码不能删除。",
                            )
                        db.execute(
                            "UPDATE licenses SET voided_at = ? WHERE account_id = ?",
                            (utc_now(), account_id),
                        )
                        audit(db, "void_license", admin=admin, account_id=account_id)
                        db.execute("COMMIT")
                    except Exception:
                        db.execute("ROLLBACK")
                        raise
                    return self._ok()
            raise ApiError(HTTPStatus.NOT_FOUND, "接口不存在。", "not_found")
        except ApiError as err:
            self._error(err)
        except Exception as exc:
            print(f"DELETE error: {exc!r}", flush=True)
            self._error(ApiError(HTTPStatus.INTERNAL_SERVER_ERROR, "服务器内部错误。"))

    def _import_legacy_license(self, body):
        code = str(body.get("activationCode", "")).strip()
        if not code:
            raise ApiError(HTTPStatus.BAD_REQUEST, "缺少激活码。")
        try:
            account_id, serial = verify_activation_code(code)
        except Exception:
            raise ApiError(HTTPStatus.BAD_REQUEST, "激活码签名无效。")

        try:
            serial_value = int(serial)
        except ValueError:
            raise ApiError(HTTPStatus.BAD_REQUEST, "激活码编号无效。")
        if serial_value < 1:
            raise ApiError(HTTPStatus.BAD_REQUEST, "激活码编号无效。")

        note = str(body.get("note", "")).strip()[:500]
        generated_by = str(body.get("generatedBy", "")).strip()[:24] or "旧记录"
        sold_by_raw = body.get("soldBy")
        sold_by = (
            str(sold_by_raw).strip()[:24]
            if sold_by_raw is not None and str(sold_by_raw).strip()
            else None
        )
        created_at = str(body.get("createdAt", "")).strip() or utc_now()
        sold_at_raw = body.get("soldAt")
        sold_at = (
            str(sold_at_raw).strip()
            if sold_at_raw is not None and str(sold_at_raw).strip()
            else None
        )

        with _db_lock, connect_db() as db:
            admin = self._admin(db)
            db.execute("BEGIN IMMEDIATE")
            try:
                existing = db.execute(
                    """
                    SELECT * FROM licenses
                    WHERE account_id = ? OR activation_code = ? OR id = ?
                    """,
                    (account_id, code, serial_value),
                ).fetchone()
                if existing is not None:
                    if (
                        existing["account_id"] == account_id
                        and existing["activation_code"] == code
                        and existing["id"] == serial_value
                    ):
                        db.execute("COMMIT")
                        return self._ok(
                            {"license": license_json(existing), "imported": False}
                        )
                    raise ApiError(
                        HTTPStatus.CONFLICT,
                        "旧激活码与服务器已有编号或账号身份冲突。",
                        "import_conflict",
                    )

                db.execute(
                    """
                    INSERT INTO licenses (
                        id, account_id, activation_code, note,
                        generated_by_admin_id, generated_by_name,
                        created_at, committed_at,
                        sold_by_admin_id, sold_by_name, sold_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        serial_value,
                        account_id,
                        code,
                        note,
                        admin["id"],
                        generated_by,
                        created_at,
                        created_at,
                        admin["id"] if sold_at is not None else None,
                        sold_by,
                        sold_at,
                    ),
                )
                audit(
                    db,
                    "import_legacy_license",
                    admin=admin,
                    account_id=account_id,
                    details={"serial": serial},
                )
                db.execute("COMMIT")
            except Exception:
                db.execute("ROLLBACK")
                raise

            row = db.execute(
                "SELECT * FROM licenses WHERE account_id = ?",
                (account_id,),
            ).fetchone()
            return self._ok(
                {"license": license_json(row), "imported": True},
                HTTPStatus.CREATED,
            )

    def _register_admin(self, body):
        if not SETUP_KEY:
            raise ApiError(
                HTTPStatus.SERVICE_UNAVAILABLE,
                "管理员注册尚未初始化。",
                "not_configured",
            )
        setup_key = str(body.get("setupKey", ""))
        if not hmac.compare_digest(setup_key, SETUP_KEY):
            raise ApiError(HTTPStatus.FORBIDDEN, "管理密钥不正确。", "forbidden")
        name = str(body.get("name", "")).strip()
        if not name or len(name) > 24:
            raise ApiError(HTTPStatus.BAD_REQUEST, "管理昵称需要在 1–24 个字符之间。")
        token = secrets.token_urlsafe(32)
        with _db_lock, connect_db() as db:
            db.execute("BEGIN IMMEDIATE")
            try:
                cur = db.execute(
                    """
                    INSERT INTO admins (name, token_hash, created_at)
                    VALUES (?, ?, ?)
                    """,
                    (name, token_hash(token), utc_now()),
                )
                admin_id = cur.lastrowid
                admin = {"id": admin_id, "name": name}
                audit(db, "register_admin", admin=admin)
                db.execute("COMMIT")
            except Exception:
                db.execute("ROLLBACK")
                raise
        self._ok(
            {"token": token, "admin": {"id": admin_id, "name": name}},
            HTTPStatus.CREATED,
        )

    def _activate(self, body):
        code = str(body.get("activationCode", "")).strip()
        claim_id = str(body.get("claimId", "")).strip()
        if not code or not claim_id:
            raise ApiError(HTTPStatus.BAD_REQUEST, "缺少激活码或激活请求标识。")
        if len(claim_id) < 16 or len(claim_id) > 128:
            raise ApiError(HTTPStatus.BAD_REQUEST, "激活请求标识格式无效。")
        try:
            account_id, serial = verify_activation_code(code)
        except Exception:
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                "激活码无效或已被修改。",
                "invalid_code",
            )

        with _db_lock, connect_db() as db:
            db.execute("BEGIN IMMEDIATE")
            try:
                row = db.execute(
                    "SELECT * FROM licenses WHERE account_id = ?",
                    (account_id,),
                ).fetchone()
                if row is None or row["activation_code"] != code or row["voided_at"]:
                    raise ApiError(
                        HTTPStatus.BAD_REQUEST,
                        "这个激活码未在授权服务器登记。",
                        "invalid_code",
                    )
                expected_serial = str(row["id"]).zfill(6)
                if serial != expected_serial:
                    raise ApiError(
                        HTTPStatus.BAD_REQUEST,
                        "激活码编号不匹配。",
                        "invalid_code",
                    )

                if row["redeemed_at"]:
                    if hmac.compare_digest(
                        row["redemption_claim_id"] or "",
                        claim_id,
                    ):
                        db.execute("COMMIT")
                        return self._ok(
                            {
                                "accountId": account_id,
                                "serial": serial,
                                "redeemedAt": row["redeemed_at"],
                                "idempotent": True,
                            }
                        )
                    raise ApiError(
                        HTTPStatus.CONFLICT,
                        "这个激活码已经注册过账号。",
                        "already_redeemed",
                    )

                now = utc_now()
                db.execute(
                    """
                    UPDATE licenses
                    SET redeemed_at = ?, redemption_claim_id = ?
                    WHERE account_id = ?
                    """,
                    (now, claim_id, account_id),
                )
                audit(
                    db,
                    "redeem_license",
                    account_id=account_id,
                    details={"serial": serial},
                )
                db.execute("COMMIT")
            except Exception:
                db.execute("ROLLBACK")
                raise

        return self._ok(
            {
                "accountId": account_id,
                "serial": serial,
                "redeemedAt": now,
                "idempotent": False,
            }
        )


def main():
    if not SETUP_KEY:
        print(
            "WARNING: LICENSE_ADMIN_SETUP_KEY is empty; admin registration is disabled.",
            flush=True,
        )
    init_db()
    server = ThreadingHTTPServer((BIND_HOST, BIND_PORT), Handler)
    print(
        f"Adventure License API listening on {BIND_HOST}:{BIND_PORT}",
        flush=True,
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
