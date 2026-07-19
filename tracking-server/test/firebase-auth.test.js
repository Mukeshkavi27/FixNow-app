import test from 'node:test';
import assert from 'node:assert/strict';
import { firebaseAdminSetupMessage } from '../src/firebase-auth.js';

test('Firebase Admin credential errors get setup guidance', () => {
  const message = firebaseAdminSetupMessage(
    new Error('Could not load the default credentials. Browse to https://cloud.google.com/docs/authentication/getting-started for more information.'),
  );

  assert.match(message, /GOOGLE_APPLICATION_CREDENTIALS/);
  assert.match(message, /fixnow-a6515/);
});

test('non-setup auth errors are not rewritten', () => {
  assert.equal(firebaseAdminSetupMessage(new Error('Authentication token is required')), null);
});
