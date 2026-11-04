import {
  ApiError, adminFromRequest, audit, getLicense, licenseJson, ok,
  parseExpectedRevision, randomHex, requireRevision, timingSafeEqualText,
  truncate, utcNow, verifyActivationCode,
} from './common.js';

export async function activate(body, env) {
  const code = String(body.activationCode ?? '').trim();
  const claimId = String(body.claimId ?? '').trim();
  if (!code || !claimId) throw new ApiError(400, '缺少激活码或激活请求标识。');
  if (claimId.length < 16 || claimId.length > 128) throw new ApiError(400, '激活请求标识格式无效。');
  let decoded;
  try { decoded = await verifyActivationCode(code); }
  catch { throw new ApiError(400, '激活码无效或已被修改。', 'invalid_code'); }

  const row = await getLicense(env, decoded.accountId);
  if (!row || row.activation_code !== code || row.voided_at) throw new ApiError(400, '这个激活码未在授权服务器登记。', 'invalid_code');
  if (decoded.serial !== String(row.id).padStart(6, '0')) throw new ApiError(400, '激活码编号不匹配。', 'invalid_code');
  if (row.redeemed_at) {
    if (await timingSafeEqualText(row.redemption_claim_id || '', claimId)) {
      return ok({ accountId: decoded.accountId, serial: decoded.serial, redeemedAt: row.redeemed_at, idempotent: true });
    }
    throw new ApiError(409, '这个激活码已经注册过账号。', 'already_redeemed');
  }

  const now = utcNow();
  const result = await env.DB.prepare(
    `UPDATE licenses SET redeemed_at = ?1, redemption_claim_id = ?2, revision = revision + 1
     WHERE account_id = ?3 AND redeemed_at IS NULL AND voided_at IS NULL AND activation_code = ?4`,
  ).bind(now, claimId, decoded.accountId, code).run();
  if ((result.meta.changes || 0) !== 1) {
    const current = await getLicense(env, decoded.accountId);
    if (current?.redeemed_at && await timingSafeEqualText(current.redemption_claim_id || '', claimId)) {
      return ok({ accountId: decoded.accountId, serial: decoded.serial, redeemedAt: current.redeemed_at, idempotent: true });
    }
    if (current?.redeemed_at) throw new ApiError(409, '这个激活码已经注册过账号。', 'already_redeemed');
    throw new ApiError(400, '这个激活码未在授权服务器登记。', 'invalid_code');
  }
  await audit(env, 'redeem_license', { accountId: decoded.accountId, details: { serial: decoded.serial } });
  return ok({ accountId: decoded.accountId, serial: decoded.serial, redeemedAt: now, idempotent: false });
}

export async function listLicenses(request, env) {
  await adminFromRequest(request, env);
  const url = new URL(request.url);
  const limitRaw = url.searchParams.get('limit') ?? '200';
  if (!/^[+-]?\d+$/.test(limitRaw)) throw new ApiError(400, 'limit 参数格式无效。', 'invalid_pagination');
  const requested = Number(limitRaw);
  if (!Number.isSafeInteger(requested)) throw new ApiError(400, 'limit 参数格式无效。', 'invalid_pagination');
  const limit = Math.min(Math.max(requested, 1), 500);
  const beforeRaw = url.searchParams.get('before_id');
  let beforeId = null;
  if (beforeRaw != null) {
    if (!/^[+-]?\d+$/.test(beforeRaw)) throw new ApiError(400, 'before_id 参数格式无效。', 'invalid_pagination');
    beforeId = Number(beforeRaw);
    if (!Number.isSafeInteger(beforeId) || beforeId < 1) throw new ApiError(400, 'before_id 参数格式无效。', 'invalid_pagination');
  }
  const result = beforeId == null
    ? await env.DB.prepare('SELECT * FROM licenses WHERE voided_at IS NULL AND activation_code IS NOT NULL ORDER BY id DESC LIMIT ?1').bind(limit + 1).all()
    : await env.DB.prepare('SELECT * FROM licenses WHERE voided_at IS NULL AND activation_code IS NOT NULL AND id < ?1 ORDER BY id DESC LIMIT ?2').bind(beforeId, limit + 1).all();
  const rows = result.results || [];
  const page = rows.slice(0, limit);
  return ok({
    licenses: page.map(licenseJson),
    nextBeforeId: rows.length > limit && page.length ? page[page.length - 1].id : null,
  });
}

export async function reserveLicense(request, body, env) {
  const admin = await adminFromRequest(request, env);
  const note = truncate(String(body.note ?? '').trim(), 500);
  const accountId = randomHex(10);
  const result = await env.DB.prepare(
    `INSERT INTO licenses (account_id, note, generated_by_admin_id, generated_by_name, created_at)
     VALUES (?1, ?2, ?3, ?4, ?5)`,
  ).bind(accountId, note, admin.id, admin.name, utcNow()).run();
  const serial = String(result.meta.last_row_id).padStart(6, '0');
  await audit(env, 'reserve_license', { admin, accountId, details: { serial } });
  return ok({ license: { serial, accountId } }, 201);
}

export async function commitLicense(request, accountId, body, env) {
  const admin = await adminFromRequest(request, env);
  const code = String(body.activationCode ?? '').trim();
  if (!code) throw new ApiError(400, '缺少激活码。');
  if (!code.startsWith('AW2.')) throw new ApiError(400, '新生成的激活码必须使用 AW2 格式。');
  let decoded;
  try { decoded = await verifyActivationCode(code); }
  catch { throw new ApiError(400, '激活码签名无效。'); }
  if (decoded.accountId !== accountId) throw new ApiError(400, '激活码账号身份不匹配。');
  let row = await getLicense(env, accountId);
  if (!row) throw new ApiError(404, '预留记录不存在。');
  if (decoded.serial !== String(row.id).padStart(6, '0')) throw new ApiError(400, '激活码编号不匹配。');
  if (row.voided_at) throw new ApiError(409, '这条记录已经作废。');
  if (row.activation_code && row.activation_code !== code) throw new ApiError(409, '这条记录已经提交过其他激活码。');
  if (!row.activation_code) {
    const result = await env.DB.prepare(
      `UPDATE licenses SET activation_code = ?1, committed_at = ?2, revision = revision + 1
       WHERE account_id = ?3 AND activation_code IS NULL AND voided_at IS NULL`,
    ).bind(code, utcNow(), accountId).run();
    if ((result.meta.changes || 0) === 1) await audit(env, 'commit_license', { admin, accountId });
    else {
      row = await getLicense(env, accountId);
      if (!row) throw new ApiError(404, '预留记录不存在。');
      if (row.voided_at) throw new ApiError(409, '这条记录已经作废。');
      if (row.activation_code !== code) throw new ApiError(409, '这条记录已经提交过其他激活码。');
    }
  }
  return ok({ license: licenseJson(await getLicense(env, accountId)) });
}

export async function setSold(request, accountId, body, env) {
  const admin = await adminFromRequest(request, env);
  const sold = body.sold;
  const expected = parseExpectedRevision(request);
  if (typeof sold !== 'boolean') throw new ApiError(400, 'sold 必须是布尔值。');
  const row = await getLicense(env, accountId);
  if (!row || row.voided_at) throw new ApiError(404, '激活码记录不存在。');
  requireRevision(row, expected);
  if (!row.activation_code) throw new ApiError(409, '激活码尚未生成完成。');
  if (sold && row.activation_code.startsWith('AW1.')) throw new ApiError(409, '旧版 AW1 激活码不能用于新的销售，请生成新的 AW2 激活码。', 'legacy_code_not_sellable');
  let stmt;
  if (sold) {
    stmt = expected == null
      ? env.DB.prepare('UPDATE licenses SET sold_by_admin_id = ?1, sold_by_name = ?2, sold_at = ?3, revision = revision + 1 WHERE account_id = ?4 AND voided_at IS NULL').bind(admin.id, admin.name, utcNow(), accountId)
      : env.DB.prepare('UPDATE licenses SET sold_by_admin_id = ?1, sold_by_name = ?2, sold_at = ?3, revision = revision + 1 WHERE account_id = ?4 AND voided_at IS NULL AND revision = ?5').bind(admin.id, admin.name, utcNow(), accountId, expected);
  } else {
    stmt = expected == null
      ? env.DB.prepare('UPDATE licenses SET sold_by_admin_id = NULL, sold_by_name = NULL, sold_at = NULL, revision = revision + 1 WHERE account_id = ?1 AND voided_at IS NULL').bind(accountId)
      : env.DB.prepare('UPDATE licenses SET sold_by_admin_id = NULL, sold_by_name = NULL, sold_at = NULL, revision = revision + 1 WHERE account_id = ?1 AND voided_at IS NULL AND revision = ?2').bind(accountId, expected);
  }
  const result = await stmt.run();
  if ((result.meta.changes || 0) !== 1) throw new ApiError(409, '这条发码记录已经被其他管理员或核销流程修改，已拒绝覆盖旧状态。', 'stale_record');
  await audit(env, sold ? 'mark_sold' : 'mark_unsold', { admin, accountId });
  return ok({ license: licenseJson(await getLicense(env, accountId)) });
}

export async function updateNote(request, accountId, body, env) {
  const admin = await adminFromRequest(request, env);
  const expected = parseExpectedRevision(request);
  const note = truncate(String(body.note ?? '').trim(), 500);
  const row = await getLicense(env, accountId);
  if (!row || row.voided_at) throw new ApiError(404, '激活码记录不存在。');
  requireRevision(row, expected);
  const stmt = expected == null
    ? env.DB.prepare('UPDATE licenses SET note = ?1, revision = revision + 1 WHERE account_id = ?2 AND voided_at IS NULL').bind(note, accountId)
    : env.DB.prepare('UPDATE licenses SET note = ?1, revision = revision + 1 WHERE account_id = ?2 AND voided_at IS NULL AND revision = ?3').bind(note, accountId, expected);
  const result = await stmt.run();
  if ((result.meta.changes || 0) !== 1) throw new ApiError(409, '这条发码记录已经被其他管理员或核销流程修改，已拒绝覆盖旧状态。', 'stale_record');
  await audit(env, 'update_note', { admin, accountId });
  return ok({ license: licenseJson(await getLicense(env, accountId)) });
}

export async function deleteLicense(request, accountId, env) {
  const admin = await adminFromRequest(request, env);
  const expected = parseExpectedRevision(request);
  const row = await getLicense(env, accountId);
  if (!row || row.voided_at) throw new ApiError(404, '激活码记录不存在。');
  requireRevision(row, expected);
  if (row.redeemed_at) throw new ApiError(409, '已核销的激活码不能删除。');
  const now = utcNow();
  const stmt = expected == null
    ? env.DB.prepare('UPDATE licenses SET voided_at = ?1, revision = revision + 1 WHERE account_id = ?2 AND voided_at IS NULL').bind(now, accountId)
    : env.DB.prepare('UPDATE licenses SET voided_at = ?1, revision = revision + 1 WHERE account_id = ?2 AND voided_at IS NULL AND revision = ?3').bind(now, accountId, expected);
  const result = await stmt.run();
  if ((result.meta.changes || 0) !== 1) throw new ApiError(409, '这条发码记录已经被其他管理员或核销流程修改，已拒绝覆盖旧状态。', 'stale_record');
  await audit(env, 'void_license', { admin, accountId });
  return ok();
}

export async function importLegacy(request, body, env) {
  const admin = await adminFromRequest(request, env);
  const code = String(body.activationCode ?? '').trim();
  if (!code) throw new ApiError(400, '缺少激活码。');
  let decoded;
  try { decoded = await verifyActivationCode(code); }
  catch { throw new ApiError(400, '激活码签名无效。'); }
  if (!/^\d+$/.test(decoded.serial)) throw new ApiError(400, '激活码编号无效。');
  const serialValue = Number(decoded.serial);
  if (!Number.isSafeInteger(serialValue) || serialValue < 1) throw new ApiError(400, '激活码编号无效。');
  const note = truncate(String(body.note ?? '').trim(), 500);
  const generatedBy = truncate(String(body.generatedBy ?? '').trim(), 24) || '旧记录';
  const soldByRaw = body.soldBy;
  const soldBy = soldByRaw == null || String(soldByRaw).trim() === '' ? null : truncate(String(soldByRaw).trim(), 24);
  const createdAt = String(body.createdAt ?? '').trim() || utcNow();
  const soldAtRaw = body.soldAt;
  const soldAt = soldAtRaw == null || String(soldAtRaw).trim() === '' ? null : String(soldAtRaw).trim();

  const findConflict = () => env.DB.prepare('SELECT * FROM licenses WHERE account_id = ?1 OR activation_code = ?2 OR id = ?3 LIMIT 1').bind(decoded.accountId, code, serialValue).first();
  const existing = await findConflict();
  if (existing) {
    if (existing.account_id === decoded.accountId && existing.activation_code === code && existing.id === serialValue) return ok({ license: licenseJson(existing), imported: false });
    throw new ApiError(409, '旧激活码与服务器已有编号或账号身份冲突。', 'import_conflict');
  }
  try {
    await env.DB.prepare(
      `INSERT INTO licenses (
         id, account_id, activation_code, note, generated_by_admin_id, generated_by_name,
         created_at, committed_at, sold_by_admin_id, sold_by_name, sold_at
       ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)`,
    ).bind(serialValue, decoded.accountId, code, note, admin.id, generatedBy, createdAt, createdAt, soldAt == null ? null : admin.id, soldBy, soldAt).run();
  } catch {
    const raced = await findConflict();
    if (raced && raced.account_id === decoded.accountId && raced.activation_code === code && raced.id === serialValue) return ok({ license: licenseJson(raced), imported: false });
    throw new ApiError(409, '旧激活码与服务器已有编号或账号身份冲突。', 'import_conflict');
  }
  await audit(env, 'import_legacy_license', { admin, accountId: decoded.accountId, details: { serial: decoded.serial } });
  return ok({ license: licenseJson(await getLicense(env, decoded.accountId)), imported: true }, 201);
}
