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
    revision INTEGER NOT NULL DEFAULT 1,
    FOREIGN KEY(generated_by_admin_id) REFERENCES admins(id),
    FOREIGN KEY(sold_by_admin_id) REFERENCES admins(id)
);

CREATE INDEX IF NOT EXISTS idx_licenses_created_at ON licenses(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_licenses_redeemed_at ON licenses(redeemed_at);
CREATE INDEX IF NOT EXISTS idx_licenses_sold_at ON licenses(sold_at);

CREATE TABLE IF NOT EXISTS audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL,
    admin_id INTEGER,
    admin_name TEXT,
    action TEXT NOT NULL,
    account_id TEXT,
    details_json TEXT NOT NULL DEFAULT '{}'
);
