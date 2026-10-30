/**
 * middleware/role.middleware.js
 * Role-Based Access Control (RBAC) middleware.
 *
 * PRD Reference: Section 10 — Security & Compliance
 *   "Role-based access control (RBAC) on all endpoints"
 *
 * PRD Reference: Section 02 — User Roles & Personas
 *   TEACHER (admin): Create/manage batches, mark payments, delete messages, remove members
 *   STUDENT (user):  View status, participate in chat, send files/messages/voice
 *
 * USAGE:
 *   // Only teachers can access this route
 *   router.post('/batches', authenticate, requireRole('teacher'), handler);
 *
 *   // Both teachers and students can access this route
 *   router.get('/chat/:id/messages', authenticate, requireRole('teacher', 'student'), handler);
 *
 * IMPORTANT:
 *   requireRole() MUST be used AFTER authenticate() in the middleware chain.
 *   authenticate() sets req.user — requireRole() reads req.user.role.
 *   Calling requireRole() without authenticate() will throw.
 */

'use strict';

const logger = require('../config/logger');

/**
 * requireRole
 * Factory function returning an Express middleware that enforces
 * that req.user.role is one of the allowed roles.
 *
 * @param {...string} allowedRoles - One or more role strings ('teacher', 'student')
 * @returns {import('express').RequestHandler}
 */
function requireRole(...allowedRoles) {
  // Validate at route-definition time (catches developer mistakes)
  if (allowedRoles.length === 0) {
    throw new Error('requireRole() called with no roles — provide at least one role.');
  }

  const validRoles = ['teacher', 'student'];
  allowedRoles.forEach((role) => {
    if (!validRoles.includes(role)) {
      throw new Error(`requireRole() received unknown role: "${role}". Valid: ${validRoles.join(', ')}`);
    }
  });

  // Return the actual middleware
  return function roleGuard(req, res, next) {
    // req.user must be set by authenticate() before this runs
    if (!req.user) {
      logger.error('requireRole() called without authenticate() — req.user is undefined');
      return res.status(500).json({
        success: false,
        message: 'Server configuration error: authentication middleware missing.',
      });
    }

    const userRole = req.user.role;

    if (!allowedRoles.includes(userRole)) {
      logger.warn(
        `RBAC denied: user ${req.user.id} (role: ${userRole}) attempted to access ` +
        `route requiring [${allowedRoles.join(', ')}]`
      );
      return res.status(403).json({
        success: false,
        message: `Access denied. This action requires one of: [${allowedRoles.join(', ')}]`,
        code: 'INSUFFICIENT_ROLE',
      });
    }

    return next();
  };
}

/**
 * requireTeacher
 * Shorthand for requireRole('teacher').
 * Used on all batch creation, fee marking, and member management routes.
 */
const requireTeacher = requireRole('teacher');

/**
 * requireStudent
 * Shorthand for requireRole('student').
 * Used on student-only routes like personal fee history.
 */
const requireStudent = requireRole('student');

/**
 * requireAny
 * Shorthand for requireRole('teacher', 'student').
 * Used on shared routes like chat message retrieval.
 */
const requireAny = requireRole('teacher', 'student');

/**
 * requireBatchOwner
 * Checks that the authenticated teacher owns the batch being accessed.
 * This prevents Teacher A from modifying Teacher B's batches.
 *
 * Reads :batchId from req.params and verifies teacher_id === req.user.id.
 * Must be used AFTER authenticate() and requireRole('teacher').
 *
 * @param {import('../models/index').Batch} BatchModel - Injected for testability
 */
function requireBatchOwner(BatchModel) {
  return async function batchOwnerGuard(req, res, next) {
    try {
      const batchId = req.params.id || req.params.batchId;

      if (!batchId) {
        return res.status(400).json({
          success: false,
          message: 'Batch ID is required in route parameters.',
        });
      }

      const batch = await BatchModel.findOne({
        where: { id: batchId },
        attributes: ['id', 'teacher_id'],
      });

      if (!batch) {
        return res.status(404).json({
          success: false,
          message: 'Batch not found.',
        });
      }

      if (batch.teacher_id !== req.user.id) {
        logger.warn(
          `Batch ownership check failed: teacher ${req.user.id} attempted to ` +
          `access batch ${batchId} owned by ${batch.teacher_id}`
        );
        return res.status(403).json({
          success: false,
          message: 'You do not have permission to modify this batch.',
          code: 'NOT_BATCH_OWNER',
        });
      }

      // Attach batch to request for downstream handlers (avoids double DB query)
      req.batch = batch;
      return next();
    } catch (error) {
      logger.error('requireBatchOwner error:', error);
      return res.status(500).json({ success: false, message: 'Server error.' });
    }
  };
}

module.exports = {
  requireRole,
  requireTeacher,
  requireStudent,
  requireAny,
  requireBatchOwner,
};