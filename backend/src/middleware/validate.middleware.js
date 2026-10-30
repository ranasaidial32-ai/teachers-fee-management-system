/**
 * middleware/validate.middleware.js
 */

'use strict';

const { validationResult, body, param, query } = require('express-validator');

// ─── Core Middleware ──────────────────────────────────────────────────────────

function validate(req, res, next) {
  const errors = validationResult(req);

  if (!errors.isEmpty()) {
    const formatted = errors.array().map((err) => ({
      field:   err.path   || err.param || 'unknown',
      message: err.msg,
      value:   err.value !== undefined ? err.value : null,
    }));

    // Debug log
    console.log('═══ VALIDATION FAILED ═══');
    console.log('PATH:', req.path);
    console.log('BODY:', JSON.stringify(req.body, null, 2));
    console.log('ERRORS:', JSON.stringify(formatted, null, 2));
    console.log('═════════════════════════');

    return res.status(422).json({
      success: false,
      message: formatted[0]?.message || 'Validation failed.',
      errors:  formatted,
    });
  }

  return next();
}

// ─── Register Validation ──────────────────────────────────────────────────────

const registerValidation = [
  body('name')
    .trim()
    .notEmpty().withMessage('Name is required.')
    .isLength({ min: 2, max: 120 })
    .withMessage('Name must be between 2 and 120 characters.'),

  body('email')
    .trim()
    .notEmpty().withMessage('Email is required.')
    .isEmail().withMessage('Must be a valid email address.')
    .normalizeEmail(),

  body('password')
    .notEmpty().withMessage('Password is required.')
    .isLength({ min: 8 }).withMessage('Password must be at least 8 characters.')
    .matches(/[A-Z]/).withMessage('Password must contain at least one uppercase letter.')
    .matches(/[0-9]/).withMessage('Password must contain at least one number.'),

  body('role')
    .notEmpty().withMessage('Role is required.')
    .isIn(['teacher', 'student']).withMessage('Role must be "teacher" or "student".'),
];

// ─── Login Validation ─────────────────────────────────────────────────────────

const loginValidation = [
  body('email')
    .trim()
    .notEmpty().withMessage('Email is required.')
    .isEmail().withMessage('Must be a valid email address.')
    .normalizeEmail(),

  body('password')
    .notEmpty().withMessage('Password is required.'),

  body('device_id')
    .optional()
    .trim()
    .isLength({ max: 255 }).withMessage('device_id too long.'),
];

// ─── Batch Validation ─────────────────────────────────────────────────────────
// ✅ KEY FIXES:
// 1. Custom date validator — isDate() with format option is unreliable
// 2. toInt() before isInt() — coerces JSON numbers and string numbers
// 3. toFloat() safety — handles edge cases

const batchValidation = [
  body('name')
    .trim()
    .notEmpty().withMessage('Batch name is required.')
    .isLength({ min: 2, max: 150 })
    .withMessage('Batch name must be between 2 and 150 characters.'),

  // ✅ FIXED: Custom validator instead of isDate() which rejects valid dates
  body('start_date')
    .notEmpty().withMessage('Start date is required.')
    .custom((value) => {
      if (typeof value !== 'string') {
        throw new Error('Start date must be a string in YYYY-MM-DD format.');
      }
      // Accept YYYY-MM-DD format only
      const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
      if (!dateRegex.test(value)) {
        throw new Error('Start date must be in YYYY-MM-DD format (e.g. 2026-05-14).');
      }
      const date = new Date(value + 'T00:00:00.000Z');
      if (isNaN(date.getTime())) {
        throw new Error('Start date is not a valid calendar date.');
      }
      return true;
    }),

  // ✅ FIXED: toInt() converts both number and string to integer
  body('fee_amount')
    .notEmpty().withMessage('Fee amount is required.')
    .toInt()
    .isInt({ min: 1, max: 999999 })
    .withMessage('Fee amount must be between ₹1 and ₹999,999.'),

  // ✅ FIXED: toInt() before isInt()
  body('duration_years')
    .notEmpty().withMessage('Duration is required.')
    .toInt()
    .isInt({ min: 1, max: 10 })
    .withMessage('Duration must be between 1 and 10 years.'),

  // ✅ FIXED: toInt() before isInt()
  body('grace_period_days')
    .notEmpty().withMessage('Grace period is required.')
    .toInt()
    .isInt({ min: 1, max: 28 })
    .withMessage('Grace period must be between 1 and 28 days.'),
];

// ─── Enroll Validation ────────────────────────────────────────────────────────

const enrollValidation = [
  param('id')
    .notEmpty().withMessage('Batch ID is required.')
    .isUUID().withMessage('Batch ID must be a valid UUID.'),

  body('student_id')
    .notEmpty().withMessage('Student ID is required.')
    .isUUID().withMessage('Student ID must be a valid UUID.'),
];

// ─── Mark Paid Validation ─────────────────────────────────────────────────────

const markPaidValidation = [
  body('fee_id')
    .notEmpty().withMessage('Fee ID is required.')
    .isUUID().withMessage('Fee ID must be a valid UUID.'),
];

// ─── Pagination Validation ────────────────────────────────────────────────────

const paginationValidation = [
  query('page')
    .optional()
    .isInt({ min: 1 }).withMessage('Page must be a positive integer.')
    .toInt(),

  query('limit')
    .optional()
    .isInt({ min: 1, max: 100 }).withMessage('Limit must be between 1 and 100.')
    .toInt(),
];

// ─── UUID Param Validation ────────────────────────────────────────────────────

function uuidParamValidation(paramName = 'id') {
  return [
    param(paramName)
      .notEmpty().withMessage(`${paramName} is required.`)
      .isUUID().withMessage(`${paramName} must be a valid UUID.`),
  ];
}

module.exports = {
  validate,
  registerValidation,
  loginValidation,
  batchValidation,
  enrollValidation,
  markPaidValidation,
  paginationValidation,
  uuidParamValidation,
};