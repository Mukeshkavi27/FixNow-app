import assert from 'node:assert/strict';
import test from 'node:test';

import { allowedOriginsFor, httpCorsOptions } from '../src/server-config.js';

test('CORS configuration normalizes and deduplicates allowed origins', () => {
  assert.deepEqual(
    allowedOriginsFor('https://fixnow.app, https://admin.fixnow.app,https://fixnow.app'),
    ['https://fixnow.app', 'https://admin.fixnow.app'],
  );
});

test('HTTP CORS accepts native calls and configured browser origins only', async () => {
  const options = httpCorsOptions(['https://fixnow.app']);
  const check = (origin) => new Promise((resolve) => {
    options.origin(origin, (error, allowed) => resolve({ error, allowed }));
  });

  assert.equal((await check(undefined)).allowed, true);
  assert.equal((await check('https://fixnow.app')).allowed, true);
  const denied = await check('https://attacker.example');
  assert.equal(denied.allowed, undefined);
  assert.equal(denied.error.code, 'CORS_ORIGIN_DENIED');
});

test('default dev CORS accepts random localhost Flutter ports', async () => {
  const options = httpCorsOptions(allowedOriginsFor());
  const check = (origin) => new Promise((resolve) => {
    options.origin(origin, (error, allowed) => resolve({ error, allowed }));
  });

  assert.equal((await check('http://localhost:59059')).allowed, true);
  assert.equal((await check('http://127.0.0.1:59059')).allowed, true);
  assert.equal((await check('https://localhost:59059')).allowed, undefined);
});
