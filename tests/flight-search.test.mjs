import test from 'node:test';
import assert from 'node:assert/strict';

const API = process.env.SKYFLOW_API || 'http://127.0.0.1:4000/api';
async function call(path, options = {}) { const response = await fetch(API + path, { ...options, headers: { 'Content-Type': 'application/json', ...(options.token ? { authorization: `Bearer ${options.token}` } : {}) } }); const body = response.status === 204 ? null : await response.json(); return { response, body }; }
async function login(email, password) { const { body } = await call('/auth/login', { method: 'POST', body: JSON.stringify({ email, password }) }); return body.token; }
const passenger = () => login('passenger@skyflow.demo', 'passenger123');
const admin = () => login('admin@skyflow.demo', 'admin123');

test('search DEL to HYD', async () => { const { body } = await call('/flights?origin=DEL&destination=HYD&date=2026-11-03'); assert.equal(body.data.length, 1); assert.equal(body.data[0].origin, 'DEL'); });
test('search HYD to BLR', async () => { const { body } = await call('/flights?origin=HYD&destination=BLR&date=2026-11-03'); assert.equal(body.data.length, 1); });
test('airport search supports name, city and IATA', async () => { for (const query of ['Rajiv Gandhi','Hyderabad','HYD']) { const { body } = await call(`/airports?q=${encodeURIComponent(query)}`); assert.ok(body.data.some(item => item.code === 'HYD')); } });
test('invalid route is rejected', async () => { const { response } = await call('/flights?origin=DEL&destination=DEL&date=2026-11-03'); assert.equal(response.status, 400); });
test('no flights available returns empty result', async () => { const { body } = await call('/flights?origin=DEL&destination=HND&date=2099-01-01'); assert.equal(body.data.length, 0); });
test('admin creates and passenger reads a flight', async () => { const token = await admin(); const number = `SF T${Date.now().toString().slice(-4)}`; const gate = `E${Date.now().toString().slice(-2)}`; const created = await call('/flights', { method: 'POST', token, body: JSON.stringify({ number, origin: 'MAA', destination: 'COK', date: '2026-12-01', scheduled: '10:00', arrival: '11:15', terminal: 'T1', gate, aircraft: 'A320', seats: 160, fare: 5000, durationMinutes: 75, travelClass: 'Economy', baggageAllowance: '20 kg' }) }); assert.equal(created.response.status, 201); const results = await call('/flights?origin=MAA&destination=COK&date=2026-12-01'); assert.ok(results.body.data.some(item => item.number === number)); });
test('passenger cannot modify flights', async () => { const token = await passenger(); const { response } = await call('/flights/fl-204', { method: 'PATCH', token, body: JSON.stringify({ status: 'Cancelled' }) }); assert.equal(response.status, 403); });
