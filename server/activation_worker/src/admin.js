import {
  ApiError, adminFromRequest, audit, ok, randomToken, sha256Hex,
  timingSafeEqualText, utcNow,
} from './common.js';

export async function registerAdmin(body, env) {
  const setupKey = (env.LICENSE_ADMIN_SETUP_KEY || '').trim();
  if (!setupKey) throw new ApiError(503, '管理员注册尚未初始化。', 'not_configured');
  const supplied = String(body.setupKey ?? '');
  if (!(await timingSafeEqualText(supplied, setupKey))) throw new ApiError(403, '管理密钥不正确。', 'forbidden');
  const name = String(body.name ?? '').trim();
  if (!name || [...name].length > 24) throw new ApiError(400, '管理昵称需要在 1–24 个字符之间。');
  const token = randomToken(32);
  const result = await env.DB.prepare(
    'INSERT INTO admins (name, token_hash, created_at) VALUES (?1, ?2, ?3)',
  ).bind(name, await sha256Hex(token), utcNow()).run();
  const admin = { id: Number(result.meta.last_row_id), name };
  await audit(env, 'register_admin', { admin });
  return ok({ token, admin }, 201);
}

export async function getAdminMe(request, env) {
  const admin = await adminFromRequest(request, env);
  return ok({ admin: { id: admin.id, name: admin.name } });
}

export async function renameAdmin(request, body, env) {
  const admin = await adminFromRequest(request, env);
  const name = String(body.name ?? '').trim();
  if (!name || [...name].length > 24) throw new ApiError(400, '管理昵称需要在 1–24 个字符之间。');
  await env.DB.prepare('UPDATE admins SET name = ?1 WHERE id = ?2').bind(name, admin.id).run();
  const updated = { id: admin.id, name };
  await audit(env, 'rename_admin', { admin: updated });
  return ok({ admin: updated });
}
