/**
 * routes/fee.routes.js
 * Express router for fee management endpoints.
 *
 * PRD Reference: Section 09 — Fee API Endpoints
 *   GET /fees/:batchId       Get fee statuses for batch (teacher)
 *   PUT /fees/mark-paid      Mark student fee as paid (teacher)
 *   GET /fees/student/:id    Student fee history (teacher)
 *   GET /fees/my-fees        Student's own fee history (student)
 */

'use strict';

const { Router } = require('express');
const { param, query } = require('express-validator');

const {
  getBatchFees,
  markPaid,
  getStudentFeeHistory,
  getMyFees,
} = require('../controllers/fee.controller');

const { authenticate }                       = require('../middleware/auth.middleware');
const { requireTeacher, requireStudent }     = require('../middleware/role.middleware');
const { validate, markPaidValidation, uuidParamValidation } =
  require('../middleware/validate.middleware');

const router = Router();

// All fee routes require authentication
router.use(authenticate);

/**
 * GET /api/v1/fees/my-fees
 * Student only — must be defined BEFORE /:batchId to avoid route conflict
 */
router.get(
  '/my-fees',
  requireStudent,
  [
    query('month')
      .optional()
      .matches(/^\d{4}-(0[1-9]|1[0-2])$/)
      .withMessage('Month must be in YYYY-MM format.'),
    query('page').optional().isInt({ min: 1 }).toInt(),
    query('limit').optional().isInt({ min: 1, max: 50 }).toInt(),
  ],
  validate,
  getMyFees
);

/**
 * GET /api/v1/fees/student/:id
 * Teacher only — view specific student's fee history
 * Must be defined BEFORE /:batchId
 */
router.get(
  '/student/:id',
  requireTeacher,
  [
    ...uuidParamValidation('id'),
    query('batch_id').optional().isUUID().withMessage('batch_id must be a valid UUID.'),
    query('page').optional().isInt({ min: 1 }).toInt(),
    query('limit').optional().isInt({ min: 1, max: 50 }).toInt(),
  ],
  validate,
  getStudentFeeHistory
);

/**
 * PUT /api/v1/fees/mark-paid
 * Teacher only — mark a specific fee record as paid
 */
router.put(
  '/mark-paid',
  requireTeacher,
  markPaidValidation,
  validate,
  markPaid
);

/**
 * GET /api/v1/fees/:batchId
 * Teacher only — get all fee statuses for a batch
 */
router.get(
  '/:batchId',
  requireTeacher,
  [
    ...uuidParamValidation('batchId'),
    query('month')
      .optional()
      .matches(/^\d{4}-(0[1-9]|1[0-2])$/)
      .withMessage('Month must be in YYYY-MM format.'),
  ],
  validate,
  getBatchFees
);

module.exports = router;