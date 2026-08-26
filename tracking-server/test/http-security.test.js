import assert from 'node:assert/strict';
import test from 'node:test';

import { createRateLimiter, securityHeaders } from '../src/http-security.js';

test('security middleware applies browser hardening headers', () => {
  const headers = new Map([['X-Powered-By', 'Express']]);
  const response = {
    setHeader: (name, value) => headers.set(name, value),
    removeHeader: (name) => headers.delete(name),
  };
  let continued = false;
  securityHeaders({}, response, () => { continued = true; });

  assert.equal(continued, true);
  assert.equal(headers.get('X-Content-Type-Options'), 'nosniff');
  assert.equal(headers.get('X-Frame-Options'), 'DENY');
  assert.equal(headers.has('X-Powered-By'), false);
});

test('rate limiter blocks requests above the configured IP limit', () => {
  let clock = 1_000;
  const limiter = createRateLimiter({
    windowMs: 60_000,
    maximumRequests: 2,
    now: () => clock,
  });
  const invoke = () => {
    const headers = new Map();
    let statusCode = 200;
    let body;
    let continued = false;
    limiter(
      { ip: '203.0.113.10' },
      {
        setHeader: (name, value) => headers.set(name, value),
        status(code) { statusCode = code; return this; },
        json(value) { body = value; },
      },
      () => { continued = true; },
    );
    return { headers, statusCode, body, continued };
  };

  assert.equal(invoke().continued, true);
  assert.equal(invoke().continued, true);
  const blocked = invoke();
  assert.equal(blocked.statusCode, 429);
  assert.equal(blocked.continued, false);
  assert.equal(blocked.body.ok, false);
  assert.equal(blocked.headers.get('Retry-After'), '60');

  clock += 60_000;
  assert.equal(invoke().continued, true);
});
