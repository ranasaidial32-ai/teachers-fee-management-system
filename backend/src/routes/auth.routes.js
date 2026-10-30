/**
 * routes/auth.routes.js
 * Added: PUT /auth/profile — update name + avatar_id
 */

'use strict';

const { Router }   = require('express');
const rateLimit    = require('express-rate-limit');
const { body }     = require('express-validator');

const {
  register,
  login,
  refresh,
  logout,
  updateFcmToken,
  getMe,
  updateProfile,  // NEW
} = require('../controllers/auth.controller');

const { authenticate } = require('../middleware/auth.middleware');

const {
  validate,
  registerValidation,
  loginValidation,
} = require('../middleware/validate.middleware');

const router = Router();

// ─── Rate Limiters ────────────────────────────────────────────────────────────

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    message: 'Too many login attempts. Please wait 15 minutes and try again.',
  },
  skipSuccessfulRequests: true,
});

const registerLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    message: 'Too many registration attempts. Please try again after an hour.',
  },
});

// Rate limiter for profile updates — prevent spam
const profileUpdateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 20,                   // 20 updates per 15 min per IP (generous limit)
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    message: 'Too many profile update requests. Please slow down.',
  },
});

// ─── Routes ───────────────────────────────────────────────────────────────────

router.post('/register', registerLimiter, registerValidation, validate, register);
router.post('/login',    loginLimiter,    loginValidation,    validate, login);

router.post(
  '/refresh',
  [
    body('refresh_token').notEmpty().withMessage('refresh_token is required.'),
    body('device_id').optional().trim().isLength({ max: 255 }),
  ],
  validate,
  refresh
);

router.post(
  '/logout',
  authenticate,
  [body('refresh_token').notEmpty().withMessage('refresh_token is required for logout.')],
  validate,
  logout
);

router.patch(
  '/fcm-token',
  authenticate,
  [
    body('fcm_token')
      .notEmpty().withMessage('fcm_token is required.')
      .isString().withMessage('fcm_token must be a string.'),
  ],
  validate,
  updateFcmToken
);

router.get('/me', authenticate, getMe);

// ── NEW: PUT /api/v1/auth/profile ─────────────────────────────────────────────
/**
 * PUT /api/v1/auth/profile
 * Protected — update display name and/or avatar_id (1–5).
 * Both fields are optional but at least one must be present.
 */
router.put(
  '/profile',
  authenticate,
  profileUpdateLimiter,
  [
    body('name')
      .optional()
      .trim()
      .isLength({ min: 2, max: 120 })
      .withMessage('Name must be between 2 and 120 characters.'),

    body('avatar_id')
      .optional()
      .isInt({ min: 1, max: 5 })
      .withMessage('avatar_id must be an integer between 1 and 5.')
      .toInt(),
  ],
  validate,
  updateProfile
);

module.exports = router;