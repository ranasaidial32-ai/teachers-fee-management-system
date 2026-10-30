/**
 * routes/batch.routes.js
 */
'use strict';

const { Router } = require('express');
const { body, param, query } = require('express-validator');

const {
  createBatch,
  listBatches,
  getBatchById,
  updateBatch,
  enrollStudent,
  removeStudent,
  searchStudents,   // ← ADD
} = require('../controllers/batch.controller');

const { authenticate }               = require('../middleware/auth.middleware');
const { requireTeacher, requireAny } = require('../middleware/role.middleware');
const {
  validate,
  batchValidation,
  enrollValidation,
  uuidParamValidation,
} = require('../middleware/validate.middleware');

const router = Router();

router.use(authenticate);

// ─── Batch CRUD ───────────────────────────────────────────────────────────────

router.post(
  '/',
  requireTeacher,
  batchValidation,
  validate,
  createBatch
);

router.get('/', requireAny, listBatches);

router.get(
  '/:id',
  requireAny,
  uuidParamValidation('id'),
  validate,
  getBatchById
);

router.put(
  '/:id',
  requireTeacher,
  [
    ...uuidParamValidation('id'),
    body('name')
      .optional().trim()
      .isLength({ min: 2, max: 150 })
      .withMessage('Name must be 2–150 characters.'),
    body('fee_amount')
      .optional()
      .isInt({ min: 1, max: 999999 })
      .withMessage('Fee amount must be ₹1–₹999,999.'),
    body('duration_years')
      .optional()
      .isInt({ min: 1, max: 10 })
      .withMessage('Duration must be 1–10 years.'),
    body('grace_period_days')
      .optional()
      .isInt({ min: 1, max: 28 })
      .withMessage('Grace period must be 1–28 days.'),
  ],
  validate,
  updateBatch
);

// ─── Student Search ───────────────────────────────────────────────────────────

/**
 * GET /api/v1/batches/:id/search-students?name=xxx
 * Teacher only — returns all non-enrolled students, filtered by name if provided.
 */
router.get(
  '/:id/search-students',
  requireTeacher,
  [
    ...uuidParamValidation('id'),
    // FIX: name is fully optional — no minimum length
    // Empty name = return all students
    query('name')
      .optional()
      .isString()
      .isLength({ max: 100 })
      .withMessage('Search name must be under 100 characters.'),
  ],
  validate,
  searchStudents,
);

// ─── Enrollment ───────────────────────────────────────────────────────────────

router.post(
  '/:id/enroll',
  requireTeacher,
  enrollValidation,
  validate,
  enrollStudent
);

router.delete(
  '/:id/enroll/:studentId',
  requireTeacher,
  [
    ...uuidParamValidation('id'),
    param('studentId')
      .notEmpty().withMessage('Student ID is required.')
      .isUUID().withMessage('Student ID must be a valid UUID.'),
  ],
  validate,
  removeStudent
);

module.exports = router;