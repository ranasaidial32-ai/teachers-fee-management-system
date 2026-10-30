/**
 * backend/src/config/firebase.js
 * Firebase Admin SDK initialisation with graceful degradation.
 *
 * PRD Reference: Section 05 — Notification System
 *   FCM data messages delivered even when app is closed/backgrounded.
 *
 * DEVELOPMENT MODE:
 *   If firebase-service-account.json is missing or invalid,
 *   Firebase is disabled gracefully — all FCM calls become no-ops.
 *   The rest of the server (auth, batches, fees, chat) works normally.
 *
 * PRODUCTION MODE:
 *   Missing or invalid Firebase credentials → server exits (fatal).
 *   FCM is required for PRD Section 05 notification delivery.
 *
 * SETUP:
 *   1. Go to Firebase Console → Project Settings → Service Accounts
 *   2. Click "Generate new private key"
 *   3. Save the downloaded JSON as:
 *      backend/src/config/firebase-service-account.json
 *   4. Never commit this file (it's in .gitignore)
 */

'use strict';

const path   = require('path');
const logger = require('./logger');

let admin        = null;
let firebaseApp  = null;
let isInitialised = false;
let isAvailable   = false;

/**
 * initFirebase
 * Idempotent initialiser — safe to call multiple times.
 * Non-fatal in development; fatal in production.
 *
 * @returns {{ app: Object|null, available: boolean }}
 */
function initFirebase() {
  // Already attempted initialisation — return cached result
  if (isInitialised) {
    return { app: firebaseApp, available: isAvailable };
  }

  isInitialised = true;
  const isProd  = process.env.NODE_ENV === 'production';

  // ── Step 1: Load firebase-admin ─────────────────────────────────────────
  try {
    admin = require('firebase-admin');
  } catch (requireError) {
    const msg = 'firebase-admin package not found. Run: npm install firebase-admin';
    if (isProd) {
      logger.error(`❌  ${msg}`);
      process.exit(1);
    }
    logger.warn(`⚠️  Firebase disabled — ${msg}`);
    return { app: null, available: false };
  }

  // ── Step 2: Resolve service account path ─────────────────────────────────
  const rawPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;

  if (!rawPath) {
    const msg = 'FIREBASE_SERVICE_ACCOUNT_PATH not set in .env';
    if (isProd) {
      logger.error(`❌  Firebase: ${msg}`);
      process.exit(1);
    }
    logger.warn(`⚠️  Firebase disabled — ${msg}`);
    return { app: null, available: false };
  }

  const serviceAccountPath = path.resolve(rawPath);

  // ── Step 3: Load service account JSON ────────────────────────────────────
  let serviceAccount;
  try {
    // Delete from require cache so file changes are picked up on restart
    delete require.cache[require.resolve(serviceAccountPath)];
    serviceAccount = require(serviceAccountPath);
  } catch (fileError) {
    const msg = `Service account file not found: ${serviceAccountPath}`;

    if (isProd) {
      logger.error(`❌  Firebase: ${msg}`);
      logger.error('    Download from: Firebase Console → Project Settings → Service Accounts');
      process.exit(1);
    }

    logger.warn('');
    logger.warn('┌─────────────────────────────────────────────────────┐');
    logger.warn('│  ⚠️  Firebase disabled (development mode)            │');
    logger.warn('│                                                     │');
    logger.warn('│  Service account file not found:                    │');
    logger.warn(`│  ${serviceAccountPath.slice(-45).padEnd(45)}  │`);
    logger.warn('│                                                     │');
    logger.warn('│  To enable FCM notifications:                       │');
    logger.warn('│  1. Go to Firebase Console                          │');
    logger.warn('│  2. Project Settings → Service Accounts             │');
    logger.warn('│  3. Generate new private key                        │');
    logger.warn('│  4. Save as firebase-service-account.json           │');
    logger.warn('│                                                     │');
    logger.warn('│  Auth, Batches, Fees, Chat work without Firebase.   │');
    logger.warn('└─────────────────────────────────────────────────────┘');
    logger.warn('');

    return { app: null, available: false };
  }

  // ── Step 4: Validate service account has required fields ─────────────────
  const requiredFields = ['type', 'project_id', 'private_key', 'client_email'];
  const missingFields  = requiredFields.filter((f) => !serviceAccount[f]);

  if (missingFields.length > 0) {
    const msg = `Service account JSON missing fields: ${missingFields.join(', ')}`;
    if (isProd) {
      logger.error(`❌  Firebase: ${msg}`);
      process.exit(1);
    }
    logger.warn(`⚠️  Firebase disabled — ${msg}`);
    return { app: null, available: false };
  }

  // ── Step 5: Check for placeholder private key ─────────────────────────────
  if (
    serviceAccount.private_key.includes('placeholder') ||
    serviceAccount.project_id.includes('placeholder') ||
    serviceAccount.client_email.includes('placeholder')
  ) {
    if (isProd) {
      logger.error('❌  Firebase: Placeholder service account detected in production.');
      process.exit(1);
    }
    logger.warn('⚠️  Firebase disabled — placeholder service account detected.');
    logger.warn('    Replace with real credentials from Firebase Console.');
    return { app: null, available: false };
  }

  // ── Step 6: Initialise Firebase Admin SDK ─────────────────────────────────
  try {
    // Check if already initialised (handles hot-reload scenarios)
    if (admin.apps.length > 0) {
      firebaseApp  = admin.apps[0];
      isAvailable  = true;
      logger.info('✅  Firebase Admin SDK reused existing app.');
      return { app: firebaseApp, available: true };
    }

    firebaseApp = admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });

    isAvailable = true;
    logger.info(`✅  Firebase Admin SDK initialised (project: ${serviceAccount.project_id})`);
    return { app: firebaseApp, available: true };

  } catch (initError) {
    const msg = initError.message || String(initError);

    if (isProd) {
      logger.error(`❌  Firebase Admin SDK initialisation failed: ${msg}`);
      process.exit(1);
    }

    logger.warn(`⚠️  Firebase disabled — init failed: ${msg}`);
    return { app: null, available: false };
  }
}

// ── FCM Helper: Check availability ───────────────────────────────────────────

/**
 * isFCMAvailable
 * Returns true if Firebase was successfully initialised.
 * Use this guard before calling sendFCMDataMessage in development.
 */
function isFCMAvailable() {
  return isAvailable;
}

// ── sendFCMDataMessage ────────────────────────────────────────────────────────

/**
 * Sends a single FCM data message.
 * PRD Section 05: Data messages surface in notification bar even
 * when app is closed, backgrounded, or device is in doze mode.
 *
 * @param {string} deviceToken
 * @param {Object} data  — all values must be strings (FCM requirement)
 * @returns {Promise<string>}  FCM message ID
 * @throws  If Firebase unavailable or send fails
 */
async function sendFCMDataMessage(deviceToken, data) {
  if (!isAvailable || !admin) {
    logger.warn('FCM sendFCMDataMessage called but Firebase is not available.');
    // Return a fake message ID in development so callers don't crash
    if (process.env.NODE_ENV !== 'production') {
      return `dev-noop-${Date.now()}`;
    }
    throw new Error('Firebase not initialised');
  }

  // FCM requires all data values to be strings
  const stringifiedData = Object.fromEntries(
    Object.entries(data).map(([k, v]) => [k, String(v)])
  );

  const message = {
    token: deviceToken,
    data:  stringifiedData,

    // Android: HIGH priority wakes doze-mode devices
    // PRD Section 05: "subject to device internet connectivity"
    android: {
      priority: 'high',
    },

    // APNs (iOS): content-available triggers background processing
    apns: {
      headers: {
        'apns-priority': '5',
      },
      payload: {
        aps: {
          'content-available': 1,
        },
      },
    },
  };

  try {
    const messageId = await admin.messaging().send(message);
    return messageId;
  } catch (fcmError) {
    // Re-throw so notification.service.js can handle stale token cleanup
    throw fcmError;
  }
}

// ── sendFCMBatch ──────────────────────────────────────────────────────────────

/**
 * Sends FCM data messages to multiple device tokens in one API call.
 * Max 500 messages per FCM batch limit.
 *
 * @param {Array<{token: string, data: Object}>} messages
 * @returns {Promise<admin.messaging.BatchResponse>}
 */
async function sendFCMBatch(messages) {
  if (!isAvailable || !admin) {
    logger.warn('FCM sendFCMBatch called but Firebase is not available.');

    if (process.env.NODE_ENV !== 'production') {
      // Return a fake BatchResponse in development
      return {
        successCount: 0,
        failureCount: messages.length,
        responses:    messages.map(() => ({
          success:   false,
          messageId: null,
          error:     { message: 'Firebase not initialised (dev mode)' },
        })),
      };
    }
    throw new Error('Firebase not initialised');
  }

  const fcmMessages = messages.map(({ token, data }) => ({
    token,
    data: Object.fromEntries(
      Object.entries(data).map(([k, v]) => [k, String(v)])
    ),
    android: { priority: 'high' },
    apns: {
      headers: { 'apns-priority': '5' },
      payload: { aps: { 'content-available': 1 } },
    },
  }));

  return admin.messaging().sendEach(fcmMessages);
}

module.exports = {
  initFirebase,
  isFCMAvailable,
  sendFCMDataMessage,
  sendFCMBatch,
};