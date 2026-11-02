import crypto from 'node:crypto';

const configuredUrl = String(process.env.SUPABASE_URL || '').trim().replace(/\/$/, '');
const anonKey = String(process.env.SUPABASE_ANON_KEY || '').trim();
const serviceRoleKey = String(process.env.SUPABASE_SERVICE_ROLE_KEY || '').trim();
const placeholder = value => !value || value.includes('your-project') || value.includes('replace-with');

export const supabaseConfigured = !placeholder(configuredUrl) && !placeholder(anonKey) && !placeholder(serviceRoleKey);
// Demo authentication is opt-in for local test fixtures only. Production never falls back to local credentials.
export const demoMode = !supabaseConfigured && process.env.DEMO_MODE === 'true' && process.env.NODE_ENV !== 'production';
export const persistenceMode = supabaseConfigured ? 'supabase' : demoMode ? 'demo' : 'unconfigured';

const request = async (path, options = {}, key = serviceRoleKey) => {
  if (!supabaseConfigured) throw new Error('Supabase is not configured');
  const response = await fetch(`${configuredUrl}${path}`, {
    ...options,
    headers: { apikey: key || anonKey, Authorization: `Bearer ${key || anonKey}`, 'Content-Type': 'application/json', ...(options.headers || {}) }
  });
  const text = await response.text();
  let body = null;
  try { body = text ? JSON.parse(text) : null; } catch { body = { message: text }; }
  if (!response.ok) { const error = new Error(body?.message || body?.error_description || 'Supabase request failed'); error.status = response.status; throw error; }
  return body;
};

export const supabaseHealth = async () => {
  if (!supabaseConfigured) return { configured: false, mode: persistenceMode, reachable: false };
  try { await request('/rest/v1/profiles?select=id&limit=1'); return { configured: true, mode: 'supabase', reachable: true }; }
  catch (error) { return { configured: true, mode: 'supabase', reachable: false, error: error.message }; }
};

export const authPasswordGrant = (email, password) => request('/auth/v1/token?grant_type=password', { method: 'POST', body: JSON.stringify({ email, password }) }, anonKey);
export const authSignUp = (email, password, userMetadata = {}) => request('/auth/v1/signup', { method: 'POST', body: JSON.stringify({ email, password, data: userMetadata }) }, anonKey);
export const authRefreshToken = refreshToken => request('/auth/v1/token?grant_type=refresh_token', { method: 'POST', body: JSON.stringify({ refresh_token: refreshToken }) }, anonKey);
export const authUser = token => request('/auth/v1/user', { headers: { Authorization: `Bearer ${token}` } }, anonKey);
export const authLogout = token => request('/auth/v1/logout', { method: 'POST', headers: { Authorization: `Bearer ${token}` } }, anonKey);
export const authUpdatePassword = (token, password) => request('/auth/v1/user', { method: 'PUT', headers: { Authorization: `Bearer ${token}` }, body: JSON.stringify({ password }) }, anonKey);
export const authCreateUser = (email, password, userMetadata = {}) => request('/auth/v1/admin/users', { method: 'POST', body: JSON.stringify({ email, password, user_metadata: userMetadata, email_confirm: false }) });
export const authInviteUser = (email, userMetadata = {}) => { const redirect = String(process.env.AUTH_REDIRECT_URL || '').trim(); const suffix = redirect ? `?redirect_to=${encodeURIComponent(redirect)}` : ''; return request(`/auth/v1/invite${suffix}`, { method: 'POST', body: JSON.stringify({ email, data: userMetadata }) }); };
export const authResetPassword = email => { const redirect = String(process.env.AUTH_REDIRECT_URL || '').trim(); const suffix = redirect ? `?redirect_to=${encodeURIComponent(redirect)}` : ''; return request(`/auth/v1/recover${suffix}`, { method: 'POST', body: JSON.stringify({ email }) }, anonKey); };
export const query = (table, params = '') => request(`/rest/v1/${table}${params}`);
export const insert = (table, value, options = '') => request(`/rest/v1/${table}${options}`, { method: 'POST', headers: { Prefer: 'return=representation' }, body: JSON.stringify(value) });
export const upsert = (table, value, conflict) => request(`/rest/v1/${table}?on_conflict=${encodeURIComponent(conflict)}`, { method: 'POST', headers: { Prefer: 'resolution=merge-duplicates,return=representation' }, body: JSON.stringify(value) });
export const update = (table, filter, value, options = '') => request(`/rest/v1/${table}?${filter}${options}`, { method: 'PATCH', headers: { Prefer: 'return=representation' }, body: JSON.stringify(value) });
export const remove = (table, filter) => request(`/rest/v1/${table}?${filter}`, { method: 'DELETE', headers: { Prefer: 'return=representation' } });
export const rpc = (name, args) => request(`/rest/v1/rpc/${name}`, { method: 'POST', body: JSON.stringify(args) });
export const randomId = () => crypto.randomUUID();
