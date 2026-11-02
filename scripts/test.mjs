import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const serverRoot = fileURLToPath(new URL('../server/', import.meta.url));
const api = 'http://127.0.0.1:4100/api';
const env = { ...process.env, DEMO_MODE: 'true', NODE_ENV: 'test', PORT: '4100', SKYFLOW_API: api };
const server = spawn(process.execPath, ['src/index.js'], { cwd: serverRoot, env, stdio: ['ignore', 'pipe', 'pipe'] });
let output = '';
server.stdout.on('data', chunk => { output += chunk.toString(); });
server.stderr.on('data', chunk => { output += chunk.toString(); });

const waitForHealth = async () => {
  const deadline = Date.now() + 15_000;
  while (Date.now() < deadline) {
    try { const response = await fetch(`${api}/health`); if (response.ok) return; } catch { /* server is still starting */ }
    await new Promise(resolve => setTimeout(resolve, 150));
  }
  throw new Error(`Test API did not start. ${output}`);
};

try {
  await waitForHealth();
  const result = spawn(process.execPath, ['--test', '--test-concurrency=1', 'tests/flight-search.test.mjs', 'tests/booking.test.mjs', 'tests/security-and-operations.test.mjs'], { cwd: root, env, stdio: 'inherit' });
  await new Promise((resolve, reject) => { result.on('exit', code => code === 0 ? resolve() : reject(new Error(`Tests exited with ${code}`))); result.on('error', reject); });
} finally {
  server.kill();
}
