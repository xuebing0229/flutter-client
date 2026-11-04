import { API_VERSION, ApiError, fail, jsonBody, ok } from './common.js';
import { getAdminMe, registerAdmin, renameAdmin } from './admin.js';
import {
  activate, commitLicense, deleteLicense, importLegacy, listLicenses,
  reserveLicense, setSold, updateNote,
} from './licenses.js';

async function route(request, env) {
  const url = new URL(request.url);
  const path = url.pathname;
  const method = request.method.toUpperCase();
  if (method === 'GET' && path === '/health') return ok({ service: 'adventure-license', version: API_VERSION });
  if (method === 'GET' && path === '/v1/admin/me') return getAdminMe(request, env);
  if (method === 'GET' && path === '/v1/licenses') return listLicenses(request, env);

  let body = null;
  if (method === 'POST' || method === 'PATCH') body = await jsonBody(request);
  if (method === 'POST' && path === '/v1/admin/register') return registerAdmin(body, env);
  if (method === 'POST' && path === '/v1/activate') return activate(body, env);
  if (method === 'POST' && path === '/v1/licenses/import') return importLegacy(request, body, env);
  if (method === 'POST' && path === '/v1/licenses/reserve') return reserveLicense(request, body, env);
  if (method === 'PATCH' && path === '/v1/admin/me') return renameAdmin(request, body, env);

  const commitMatch = path.match(/^\/v1\/licenses\/([^/]+)\/commit$/);
  if (method === 'POST' && commitMatch) return commitLicense(request, decodeURIComponent(commitMatch[1]), body, env);
  const soldMatch = path.match(/^\/v1\/licenses\/([^/]+)\/sold$/);
  if (method === 'POST' && soldMatch) return setSold(request, decodeURIComponent(soldMatch[1]), body, env);
  const noteMatch = path.match(/^\/v1\/licenses\/([^/]+)\/note$/);
  if (method === 'PATCH' && noteMatch) return updateNote(request, decodeURIComponent(noteMatch[1]), body, env);
  const deleteMatch = path.match(/^\/v1\/licenses\/([^/]+)$/);
  if (method === 'DELETE' && deleteMatch) return deleteLicense(request, decodeURIComponent(deleteMatch[1]), env);
  throw new ApiError(404, '接口不存在。', 'not_found');
}

export default {
  async fetch(request, env) {
    try { return await route(request, env); }
    catch (error) {
      if (error instanceof ApiError) return fail(error);
      console.error('Unhandled activation worker error', error);
      return fail(new ApiError(500, '服务器内部错误。'));
    }
  },
};
