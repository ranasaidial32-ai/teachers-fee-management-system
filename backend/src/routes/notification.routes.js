/**
 * routes/notification.routes.js
 * Express router for notification endpoints.
 *
 * PRD Reference: Section 05 — Notification System
 *
 * ENDPOINTS:
 *   GET /notifications/my                        Student's notification history
 *   GET /notifications/batch/:batchId/stats      Teacher's batch delivery stats
 *   GET /notifications/failed                    Teacher's failed notifications
 */

'use strict';

const { Router } = require('express');
const { query }  = require('express-validator');

const {
  getMyNotifications,
  getBatchNotificationStats,
  getFailedNotifications,
} = require('../controllers/notification.controller');

const { authenticate }                    = require('../middleware/auth.middleware');
const { requireStudent, requireTeacher }  = require('../middleware/role.middleware');
const { validate, uuidParamValidation }   = require('../middleware/validate.middleware');

const router = Router();

router.use(authenticate);

/**
 * GET /api/v1/notifications/my
 * Student only
 */
router.get(
  '/my',
  requireStudent,
  [
    query('type')
      .optional()
      .isIn(['fee_overdue', 'fee_paid', 'file_shared', 'chat_message'])
      .withMessage('Invalid notification type.'),
    query('page').optional().isInt({ min: 1 }).toInt(),
    query('limit').optional().isInt({ min: 1, max: 50 }).toInt(),
  ],
  validate,
  getMyNotifications
);

/**
 * GET /api/v1/notifications/batch/:batchId/stats
 * Teacher only — delivery rate stats per PRD success metric
 */
router.get(
  '/batch/:batchId/stats',
  requireTeacher,
  [
    ...uuidParamValidation('batchId'),
    query('month')
      .optional()
      .matches(/^\d{4}-(0[1-9]|1[0-2])$/)
      .withMessage('Month must be YYYY-MM format.'),
  ],
  validate,
  getBatchNotificationStats
);

/**
 * GET /api/v1/notifications/failed
 * Teacher only — view failed notification dispatch records
 */
router.get(
  '/failed',
  requireTeacher,
  [
    query('batch_id').optional().isUUID().withMessage('batch_id must be a valid UUID.'),
    query('limit').optional().isInt({ min: 1, max: 100 }).toInt(),
  ],
  validate,
  getFailedNotifications
);

module.exports = router;