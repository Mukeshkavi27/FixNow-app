import { readFileSync } from 'node:fs';
import { applicationDefault, cert, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { getStorage } from 'firebase-admin/storage';
import { buildPrincipal } from './rbac.js';

const projectId = process.env.FIREBASE_PROJECT_ID
  ?? process.env.GOOGLE_CLOUD_PROJECT
  ?? process.env.GCLOUD_PROJECT
  ?? 'fixnow-a6515';

if (getApps().length === 0) {
  const serviceAccountPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  const serviceAccount = serviceAccountPath
    ? JSON.parse(readFileSync(serviceAccountPath, 'utf8'))
    : serviceAccountJson
      ? JSON.parse(serviceAccountJson)
      : null;
  initializeApp({
    // A local service-account key signs custom login tokens directly. This
    // avoids a runtime dependency on the IAM Credentials API.
    credential: serviceAccount ? cert(serviceAccount) : applicationDefault(),
    projectId,
  });
}

export const firebaseAuth = getAuth();
export const firestore = getFirestore();
export const firebaseMessaging = getMessaging();
export const firebaseStorage = getStorage();

export function firebaseAdminSetupMessage(error) {
  const message = String(error?.message ?? '');
  if (
    message.includes('Could not load the default credentials')
    || message.includes('Unable to detect a Project Id')
  ) {
    return 'FixNow admin server is missing Firebase Admin credentials. Set FIREBASE_PROJECT_ID and either GOOGLE_APPLICATION_CREDENTIALS or FIREBASE_SERVICE_ACCOUNT_JSON, then restart the tracking server.';
  }
  return null;
}

function bearerToken(value) {
  const match = /^Bearer\s+(.+)$/i.exec(String(value ?? ''));
  return match?.[1] ?? null;
}

export async function principalForToken(token) {
  if (!token) throw new Error('Authentication token is required');
  const decoded = await firebaseAuth.verifyIdToken(token, true);
  const profile = await firestore.collection('users').doc(decoded.uid).get();
  if (!profile.exists) throw new Error('FixNow user profile was not found');
  return buildPrincipal(decoded.uid, profile.data());
}

export async function authenticateRequest(req, res, next) {
  try {
    req.principal = await principalForToken(bearerToken(req.headers.authorization));
    next();
  } catch (error) {
    const setupMessage = firebaseAdminSetupMessage(error);
    res.status(setupMessage ? 500 : 401).json({
      ok: false,
      error: setupMessage ?? error.message,
    });
  }
}

export async function authenticateSocket(socket, next) {
  try {
    const token = socket.handshake.auth?.token
      ?? bearerToken(socket.handshake.headers?.authorization);
    socket.data.principal = await principalForToken(token);
    next();
  } catch (error) {
    const authError = new Error('Unauthorized');
    const setupMessage = firebaseAdminSetupMessage(error);
    authError.data = {
      code: setupMessage ? 'FIREBASE_ADMIN_NOT_CONFIGURED' : 'AUTH_REQUIRED',
      message: setupMessage ?? error.message,
    };
    next(authError);
  }
}
