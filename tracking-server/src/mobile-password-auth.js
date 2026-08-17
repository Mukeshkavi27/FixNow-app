const attemptWindowMs = 15 * 60 * 1000;
const maxAttemptsPerWindow = 5;
const attempts = new Map();

export function normalizeIndianMobile(value) {
  const digits = String(value ?? '').replace(/\D/g, '');
  if (/^[6-9]\d{9}$/.test(digits)) return `+91${digits}`;
  if (/^91[6-9]\d{9}$/.test(digits)) return `+${digits}`;
  throw new Error('Enter a valid Indian mobile number');
}

export function registerMobilePasswordAuth(app, { auth, firestore }) {
  app.post('/auth/mobile-password', async (req, res) => {
    const ip = req.ip || 'unknown';
    try {
      const phoneNormalized = normalizeIndianMobile(req.body?.phone);
      const password = String(req.body?.password ?? '');
      const role = String(req.body?.role ?? '').trim();
      if (password.length < 6) throw new Error('Invalid mobile number or password');
      if (!['customer', 'technician', 'branchAdmin', 'superAdmin'].includes(role)) {
        throw new Error('Select the account type you want to sign in to');
      }
      enforceRateLimit(`${ip}:${phoneNormalized}`);

      const profiles = await firestore.collection('users')
        .where('phoneNormalized', '==', phoneNormalized)
        .get();
      const matchedProfiles = profiles.docs.filter((profile) => profile.data().role === role);
      if (matchedProfiles.length !== 1) {
        throw new Error('Invalid mobile number or password');
      }
      const profile = matchedProfiles[0];
      const authUser = await auth.getUser(profile.id);
      if (!authUser.email) throw new Error('This account cannot use mobile login yet');

      // Firebase Auth remains the password authority. The API key identifies
      // the Firebase project but is never returned to the mobile app here.
      const apiKey = process.env.FIREBASE_WEB_API_KEY;
      if (!apiKey) throw new Error('Mobile login server is not configured');
      const response = await fetch(
        `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${encodeURIComponent(apiKey)}`,
        {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ email: authUser.email, password, returnSecureToken: true }),
        },
      );
      const result = await response.json();
      if (!response.ok || result.localId !== profile.id) {
        throw new Error('Invalid mobile number or password');
      }
      const customToken = await auth.createCustomToken(profile.id);
      attempts.delete(`${ip}:${phoneNormalized}`);
      res.json({ ok: true, customToken });
    } catch (error) {
      const message = String(error?.message ?? 'Unable to sign in');
      const status = message === 'Too many sign-in attempts. Try again later.' ? 429 : 401;
      res.status(status).json({ ok: false, error: message });
    }
  });
}

function enforceRateLimit(key) {
  const now = Date.now();
  const active = (attempts.get(key) ?? []).filter((time) => now - time < attemptWindowMs);
  if (active.length >= maxAttemptsPerWindow) {
    throw new Error('Too many sign-in attempts. Try again later.');
  }
  active.push(now);
  attempts.set(key, active);
}
