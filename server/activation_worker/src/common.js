export const PUBLIC_KEY_B64URL = 'y4fObOqoJ0gXSs8oyp9av0JiKpYj5HIA-0_PxTZ30eQ';
export const API_VERSION = 1;
export const MAX_BODY_BYTES = 1024 * 1024;
const encoder = new TextEncoder();
const decoder = new TextDecoder();

export class ApiError extends Error {
  constructor(status, message, code = 'error') {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function utcNow() {
  return new Date().toISOString();
}

function base64UrlDecode(value) {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized + '='.repeat((4 - (normalized.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function base64UrlEncode(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

export function randomHex(byteLength) {
  const bytes = crypto.getRandomValues(new Uint8Array(byteLength));
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

export function randomToken(byteLength = 32) {
  return base64UrlEncode(crypto.getRandomValues(new Uint8Array(byteLength)));
}

export function truncate(value, maxCodePoints) {
  return [...String(value)].slice(0, maxCodePoints).join('');
}

export async function sha256Hex(value) {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(value)));
  return Array.from(digest, (b) => b.toString(16).padStart(2, '0')).join('');
}

export async function timingSafeEqualText(a, b) {
  const [left, right] = await Promise.all([
    crypto.subtle.digest('SHA-256', encoder.encode(a)),
    crypto.subtle.digest('SHA-256', encoder.encode(b)),
  ]);
  const x = new Uint8Array(left);
  const y = new Uint8Array(right);
  let diff = 0;
  for (let i = 0; i < x.length; i += 1) diff |= x[i] ^ y[i];
  return diff === 0;
}

export async function verifyActivationCode(code) {
  const parts = code.trim().split('.');
  if (parts.length !== 3) throw new Error('invalid code');
  const expectedVersion = parts[0] === 'AW1' ? 1 : parts[0] === 'AW2' ? 2 : null;
  if (expectedVersion == null) throw new Error('invalid code');
  const payloadBytes = base64UrlDecode(parts[1]);
  const signature = base64UrlDecode(parts[2]);
  const publicKey = await crypto.subtle.importKey(
    'raw', base64UrlDecode(PUBLIC_KEY_B64URL), { name: 'Ed25519' }, false, ['verify'],
  );
  const valid = await crypto.subtle.verify('Ed25519', publicKey, signature, payloadBytes);
  if (!valid) throw new Error('invalid signature');
  const payload = JSON.parse(decoder.decode(payloadBytes));
  if (!payload || typeof payload !== 'object' || payload.v !== expectedVersion) throw new Error('invalid version');
  if (typeof payload.a !== 'string' || !payload.a) throw new Error('missing account id');
  if (typeof payload.s !== 'string' || !payload.s) throw new Error('missing serial');
  return { accountId: payload.a, serial: payload.s };
}

export function licenseJson(row) {
  const status = row.voided_at ? 'void'
    : row.redeemed_at ? 'redeemed'
      : row.sold_at ? 'sold'
        : row.activation_code ? 'unused' : 'reserved';
  return {
    serial: String(row.id).padStart(6, '0'),
    accountId: row.account_id,
    activationCode: row.activation_code,
    note: row.note,
    generatedBy: row.generated_by_name,
    createdAt: row.created_at,
    soldBy: row.sold_by_name,
    soldAt: row.sold_at,
    redeemedAt: row.redeemed_at,
    status,
    revision: row.revision,
  };
}

export function jsonResponse(status, data) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    },
  });
}

export function ok(data = {}, status = 200) {
  return jsonResponse(status, { ok: true, ...data });
}

export function fail(error) {
  return jsonResponse(error.status || 500, {
    ok: false,
    error: error.code || 'error',
    message: error.message || '服务器内部错误。',
  });
}

export async function jsonBody(request) {
  const lengthHeader = request.headers.get('content-length');
  if (lengthHeader && Number(lengthHeader) > MAX_BODY_BYTES) throw new ApiError(413, '请求过大。');
  const raw = new Uint8Array(await request.arrayBuffer());
  if (raw.byteLength === 0) return {};
  if (raw.byteLength > MAX_BODY_BYTES) throw new ApiError(413, '请求过大。');
  let value;
  try {
    value = JSON.parse(decoder.decode(raw));
  } catch {
    throw new ApiError(400, 'JSON 格式无效。');
  }
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new ApiError(400, '请求内容必须是对象。');
  return value;
}

export async function adminFromRequest(request, env) {
  const auth = request.headers.get('authorization') || '';
  if (!auth.startsWith('Bearer ')) throw new ApiError(401, '缺少管理员身份。', 'unauthorized');
  const token = auth.slice(7).trim();
  if (!token) throw new ApiError(401, '缺少管理员身份。', 'unauthorized');
  const digest = await sha256Hex(token);
  const row = await env.DB.prepare(
    'SELECT id, name, created_at FROM admins WHERE token_hash = ?1 AND disabled_at IS NULL',
  ).bind(digest).first();
  if (!row) throw new ApiError(401, '管理员身份无效。', 'unauthorized');
  return row;
}

export async function audit(env, action, { admin = null, accountId = null, details = {} } = {}) {
  await env.DB.prepare(
    `INSERT INTO audit_log
       (created_at, admin_id, admin_name, action, account_id, details_json)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6)`,
  ).bind(utcNow(), admin?.id ?? null, admin?.name ?? null, action, accountId, JSON.stringify(details)).run();
}

export function parseExpectedRevision(request) {
  const raw = request.headers.get('x-license-revision');
  if (raw == null || raw.trim() === '') return null;
  if (!/^\d+$/.test(raw.trim())) throw new ApiError(400, '发码记录版本格式无效。', 'invalid_revision');
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || value < 1) throw new ApiError(400, '发码记录版本格式无效。', 'invalid_revision');
  return value;
}

export function requireRevision(row, expected) {
  if (expected != null && row.revision !== expected) {
    throw new ApiError(409, '这条发码记录已经被其他管理员或核销流程修改，已拒绝覆盖旧状态。', 'stale_record');
  }
}

export async function getLicense(env, accountId) {
  return env.DB.prepare('SELECT * FROM licenses WHERE account_id = ?1').bind(accountId).first();
}
