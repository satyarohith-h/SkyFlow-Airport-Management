import test from 'node:test';
import assert from 'node:assert/strict';

const API = process.env.SKYFLOW_API || 'http://127.0.0.1:4000/api';
async function call(path, options = {}) {
  const response = await fetch(API + path, { ...options, headers: { 'Content-Type': 'application/json', ...(options.token ? { authorization: `Bearer ${options.token}` } : {}) } });
  const body = response.status === 204 ? null : await response.json();
  return { response, body };
}
async function login(email, password) { return (await call('/auth/login', { method: 'POST', body: JSON.stringify({ email, password }) })).body.token; }

test('health and readiness identify demo persistence honestly', async () => {
  const health = await call('/health');
  assert.equal(health.response.status, 200);
  assert.ok(['demo', 'supabase', 'unconfigured'].includes(health.body.mode));
  const readiness = await call('/readiness');
  assert.equal(readiness.body.ok, health.body.mode === 'demo' || health.body.mode === 'supabase');
});

test('public registration always creates a passenger', async () => {
  const email = `audit-${Date.now()}@example.com`;
  const result = await call('/auth/register', { method: 'POST', body: JSON.stringify({ name: 'Audit Passenger', email, password: 'secure-pass-123' }) });
  assert.equal(result.response.status, 201);
  assert.equal(result.body.user.role, 'passenger');
  assert.equal(result.body.user.password, undefined);
});

test('passenger cannot access reports or administer accounts', async () => {
  const token = await login('passenger@skyflow.demo', 'passenger123');
  assert.equal((await call('/reports/summary', { token })).response.status, 403);
  assert.equal((await call('/admin/users', { token })).response.status, 403);
});

test('support ticket ownership and admin reporting work', async () => {
  const passengerToken = await login('passenger@skyflow.demo', 'passenger123');
  const created = await call('/support/tickets', { method: 'POST', token: passengerToken, body: JSON.stringify({ subject: 'Seat question', description: 'Please review my seat assignment.' }) });
  assert.equal(created.response.status, 201);
  const listed = await call('/support/tickets', { token: passengerToken });
  assert.ok(listed.body.data.some(item => item.id === created.body.data.id));
  const adminToken = await login('admin@skyflow.demo', 'admin123');
  const report = await call('/reports/summary', { token: adminToken });
  assert.equal(report.response.status, 200);
  assert.equal(typeof report.body.data.flights, 'number');
});
