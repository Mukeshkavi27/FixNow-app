export function securityHeaders(_req, res, next) {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  res.removeHeader('X-Powered-By');
  next();
}

export function createRateLimiter({
  windowMs,
  maximumRequests,
  message = 'Too many requests. Try again later.',
  now = Date.now,
}) {
  const clients = new Map();
  return (req, res, next) => {
    const currentTime = now();
    const key = String(req.ip || req.socket?.remoteAddress || 'unknown');
    let entry = clients.get(key);
    if (!entry || currentTime >= entry.resetAt) {
      entry = { count: 0, resetAt: currentTime + windowMs };
      clients.set(key, entry);
    }
    entry.count += 1;
    res.setHeader('RateLimit-Limit', String(maximumRequests));
    res.setHeader(
      'RateLimit-Remaining',
      String(Math.max(0, maximumRequests - entry.count)),
    );
    res.setHeader('RateLimit-Reset', String(Math.ceil(entry.resetAt / 1000)));
    if (entry.count > maximumRequests) {
      res.setHeader(
        'Retry-After',
        String(Math.max(1, Math.ceil((entry.resetAt - currentTime) / 1000))),
      );
      res.status(429).json({ ok: false, error: message });
      return;
    }
    next();
  };
}
