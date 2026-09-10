import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { performance } from 'node:perf_hooks';

const port = 18088;
const requestCount = 5000;
const concurrency = 100;
const baseUrl = `http://127.0.0.1:${port}`;

function percentile(values, value) {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * value) - 1)];
}

async function waitForServer() {
  const deadline = Date.now() + 20_000;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`${baseUrl}/health`);
      if (response.ok) return;
    } catch (_) {
      // The child is still starting.
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('Tracking server did not become healthy within 20 seconds.');
}

async function runLoad() {
  let cursor = 0;
  let errors = 0;
  const latencies = [];
  const workers = Array.from({ length: concurrency }, async () => {
    while (cursor < requestCount) {
      cursor += 1;
      const started = performance.now();
      try {
        const response = await fetch(`${baseUrl}/health`);
        const body = await response.json();
        if (!response.ok || body.ok !== true) errors += 1;
      } catch (_) {
        errors += 1;
      } finally {
        latencies.push(performance.now() - started);
      }
    }
  });
  const started = performance.now();
  await Promise.all(workers);
  const elapsedMs = performance.now() - started;
  const report = {
    passed: errors === 0,
    requests: requestCount,
    concurrency,
    requestsPerSecond: Number((requestCount / (elapsedMs / 1000)).toFixed(2)),
    p50Ms: Number(percentile(latencies, 0.5).toFixed(2)),
    p95Ms: Number(percentile(latencies, 0.95).toFixed(2)),
    p99Ms: Number(percentile(latencies, 0.99).toFixed(2)),
    errors,
  };
  console.log(JSON.stringify(report, null, 2));
  assert.equal(errors, 0);
}

const child = spawn(process.execPath, ['src/index.js'], {
  cwd: new URL('..', import.meta.url),
  env: {
    ...process.env,
    PORT: String(port),
    NODE_ENV: 'test',
    FIREBASE_PROJECT_ID: process.env.GCLOUD_PROJECT ?? 'demo-fixnow-scale-test',
  },
  stdio: ['ignore', 'pipe', 'pipe'],
});

let childErrors = '';
child.stderr.on('data', (chunk) => { childErrors += chunk; });

try {
  await waitForServer();
  await runLoad();
} finally {
  child.kill('SIGTERM');
  await new Promise((resolve) => child.once('exit', resolve));
}

if (childErrors.trim()) process.stderr.write(childErrors);
