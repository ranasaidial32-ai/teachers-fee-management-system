/**
 * routes/chat.routes.js
 * Express router for chat REST endpoints.
 *
 * PRD Reference: Section 09 — Chat & Files API Endpoints
 *   GET    /chat/:batchId/messages                           Get paginated message history
 *   GET    /chat/:batchId/messages/:messageId/readers        Get reader list (teacher only)
 *   DELETE /chat/:batchId/messages/:messageId                Delete message (teacher only)
 *
 * NOTE: Real-time message sending/receiving is via Socket.IO,
 *       not REST. See src/socket/socket.js.
 */

'use strict';

const { Router } = require('express');
const { param, query } = require('express-validator');

const {
  getMessages,
  deleteMessage,
  getMessageReaders,
} = require('../controllers/chat.controller');

const { authenticate }                       = require('../middleware/auth.middleware');
const { requireAny, requireTeacher }         = require('../middleware/role.middleware');
const { validate, uuidParamValidation }      = require('../middleware/validate.middleware');

const router = Router();

// All chat routes require a valid JWT
router.use(authenticate);

// ─────────────────────────────────────────────────────────────────────────────
// IMPORTANT: Route ordering matters in Express.
// The '/readers' literal segment MUST be registered BEFORE '/:messageId'
// otherwise Express matches "readers" as the :messageId parameter value
// and never reaches the readers handler.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * GET /api/v1/chat/:batchId/messages
 * Both teacher and enrolled student can retrieve message history.
 * Returns messages enriched with delivery_summary (downloaded_count,
 * reader_count, first_reader) for bubble tick + avatar rendering.
 */
router.get(
  '/:batchId/messages',
  requireAny,
  [
    ...uuidParamValidation('batchId'),
    query('before')
      .optional()
      .isUUID()
      .withMessage('before must be a valid message UUID.'),
    query('limit')
      .optional()
      .isInt({ min: 1, max: 50 })
      .toInt(),
  ],
  validate,
  getMessages
);

/**
 * GET /api/v1/chat/:batchId/messages/:messageId/readers
 * Teacher only — returns the full list of students who have read
 * a specific message, with name, email, and read timestamp.
 *
 * Used by the reader list bottom sheet when teacher taps the
 * "9+" avatar indicator on a message bubble.
 *
 * MUST be declared before /:batchId/messages/:messageId (DELETE)
 * to prevent Express matching "readers" as :messageId.
 */
router.get(
  '/:batchId/messages/:messageId/readers',
  requireTeacher,
  [
    ...uuidParamValidation('batchId'),
    param('messageId')
      .notEmpty().withMessage('Message ID is required.')
      .isUUID().withMessage('Message ID must be a valid UUID.'),
  ],
  validate,
  getMessageReaders
);

/**
 * DELETE /api/v1/chat/:batchId/messages/:messageId
 * Teacher only — PRD Section 06 permissions matrix:
 * "Delete any message — Teacher: Yes, Student: No"
 *
 * Soft-deletes the message, clears delivery rows,
 * and broadcasts message_deleted via Socket.IO to the batch room.
 */
router.delete(
  '/:batchId/messages/:messageId',
  requireTeacher,
  [
    ...uuidParamValidation('batchId'),
    param('messageId')
      .notEmpty().withMessage('Message ID is required.')
      .isUUID().withMessage('Message ID must be a valid UUID.'),
  ],
  validate,
  deleteMessage
);

module.exports = router;