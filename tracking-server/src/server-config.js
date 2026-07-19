const developmentOrigins = [
  'http://localhost:5200',
  'http://127.0.0.1:5200',
  'http://localhost:*',
  'http://127.0.0.1:*',
];

export function allowedOriginsFor(value = process.env.CORS_ORIGIN) {
  const configured = String(value ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
  return configured.length > 0 ? [...new Set(configured)] : developmentOrigins;
}

export function httpCorsOptions(origins) {
  const allowed = new Set(origins);
  return {
    origin(origin, callback) {
      // Native applications and trusted server calls do not send Origin.
      if (!origin || allowed.has(origin) || allowed.has(localhostWildcard(origin))) {
        callback(null, true);
        return;
      }
      const error = new Error('Origin is not allowed by FixNow CORS policy');
      error.code = 'CORS_ORIGIN_DENIED';
      callback(error);
    },
  };
}

function localhostWildcard(origin) {
  try {
    const url = new URL(origin);
    if (url.protocol !== 'http:') return '';
    if (url.hostname !== 'localhost' && url.hostname !== '127.0.0.1') {
      return '';
    }
    return `${url.protocol}//${url.hostname}:*`;
  } catch {
    return '';
  }
}
