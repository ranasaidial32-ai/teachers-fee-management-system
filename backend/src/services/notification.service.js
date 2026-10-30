/**
 * services/notification.service.js
 * Central service for sending FCM push notifications.
 *
 * PRD Reference: Section 05 — Notification System
 *   FCM data messages delivered even when app is closed/backgrounded
 *   No PII stored in FCM notification payloads (PRD Section 10)
 *
 * This service is the single point of truth for FCM dispatch.
 * It handles:
 *   1. Single notification dispatch
 *   2. Batch notification dispatch
 *   3. Notification log persistence
 *   4. Stale token cleanup (PRD Section 11)
 *
 * NOTIFICATION TYPES:
 *   fee_overdue  — Grace period expired without payment (from cron)
 *   fee_paid     — Teacher marked fee as paid
 *   file_shared  — Teacher shared a new file (from socket/file controller)
 *   chat_message — New chat message (optional, per user preference)
 *
 * PII POLICY (PRD Section 10):
 *   No student names, emails, or personal data in FCM payloads.
 *   Payloads contain only: type, batch_id, batch_name, month, amount_due.
 *   The Flutter client looks up display details from local DB/cache.
 */

'use strict';

const { v4: uuidv4 } = require('uuid');
const { sendFCMDataMessage, sendFCMBatch } = require('../config/firebase');
const { Notification, User } = require('../models/index');
const logger = require('../config/logger');

// ─── Notification Type Payloads ───────────────────────────────────────────────

/**
 * buildFeeOverduePayload
 * PRD Section 05 — FCM Payload Example
 *
 * @param {Object} params
 * @returns {Object} FCM data payload (all string values)
 */
function buildFeeOverduePayload({ batchId, batchName, month, amountDue, feeId }) {
  return {
    type:        'fee_overdue',
    batch_id:    batchId,
    batch_name:  batchName,
    month,
    amount_due:  String(amountDue),
    fee_id:      feeId,
  };
}

/**
 * buildFeePaidPayload
 * @param {Object} params
 * @returns {Object}
 */
function buildFeePaidPayload({ batchId, batchName, month, amountPaid, feeId }) {
  return {
    type:         'fee_paid',
    batch_id:     batchId,
    batch_name:   batchName,
    month,
    amount_paid:  String(amountPaid),
    fee_id:       feeId,
  };
}

/**
 * buildFileSharedPayload
 * @param {Object} params
 * @returns {Object}
 */
function buildFileSharedPayload({ batchId, batchName, fileRecordId, originalName, uploaderName }) {
  return {
    type:          'file_shared',
    batch_id:      batchId,
    batch_name:    batchName,
    file_record_id: fileRecordId,
    file_name:     originalName,
    uploader_name: uploaderName,
    // No URLs in FCM payload — client fetches from REST API
  };
}

// ─── Core Dispatch Functions ──────────────────────────────────────────────────

/**
 * sendNotification
 * Sends a single FCM notification and logs the result.
 *
 * @param {Object} params
 * @param {string} params.userId       - Recipient user ID
 * @param {string} params.batchId      - Related batch ID (optional)
 * @param {string} params.feeId        - Related fee ID (optional)
 * @param {string} params.type         - Notification type
 * @param {Object} params.payload      - FCM data payload
 * @param {string} params.deviceToken  - FCM device token
 *
 * @returns {Promise<{ success: boolean, notificationId: string }>}
 */
async function sendNotification({
  userId,
  batchId  = null,
  feeId    = null,
  type,
  payload,
  deviceToken,
}) {
  const notificationId = uuidv4();

  // Create notification log row (status: queued)
  const notification = await Notification.create({
    id:                    notificationId,
    user_id:               userId,
    batch_id:              batchId,
    fee_id:                feeId,
    type,
    fcm_payload:           payload,
    device_token_snapshot: deviceToken,
    status:                'queued',
  });

  try {
    const fcmMessageId = await sendFCMDataMessage(deviceToken, payload);

    // Update notification as sent
    await notification.update({
      status:         'sent',
      fcm_message_id: fcmMessageId,
      sent_at:        new Date(),
    });

    logger.info(
      `Notification sent: type=${type} user=${userId} fcmId=${fcmMessageId}`
    );

    return { success: true, notificationId };

  } catch (fcmError) {
    // Update notification as failed
    await notification.update({
      status:        'failed',
      error_message: fcmError.message,
    });

    logger.error(
      `Notification failed: type=${type} user=${userId} error=${fcmError.message}`
    );

    // Handle stale token (PRD Section 11)
    await handleStaleToken(fcmError, userId);

    return { success: false, notificationId };
  }
}

/**
 * sendBatchNotifications
 * Sends notifications to multiple users efficiently using FCM batch API.
 *
 * @param {Array<{
 *   userId: string,
 *   batchId: string,
 *   feeId: string,
 *   type: string,
 *   payload: Object,
 *   deviceToken: string
 * }>} notifications
 *
 * @returns {Promise<{ sent: number, failed: number }>}
 */
async function sendBatchNotifications(notifications) {
  const stats = { sent: 0, failed: 0 };

  // Filter out notifications without device tokens
  const valid = notifications.filter((n) => {
    if (!n.deviceToken) {
      logger.warn(`Skipping notification for user ${n.userId} — no FCM token`);
      return false;
    }
    return true;
  });

  if (valid.length === 0) return stats;

  // Build FCM messages
  const fcmMessages = valid.map((n) => ({
    token: n.deviceToken,
    data:  n.payload,
  }));

  // Send batch
  const batchResponse = await sendFCMBatch(fcmMessages);

  // Process results
  await Promise.allSettled(
    batchResponse.responses.map(async (response, index) => {
      const notif = valid[index];

      if (response.success) {
        stats.sent++;
        await Notification.create({
          id:                    uuidv4(),
          user_id:               notif.userId,
          batch_id:              notif.batchId || null,
          fee_id:                notif.feeId   || null,
          type:                  notif.type,
          fcm_payload:           notif.payload,
          device_token_snapshot: notif.deviceToken,
          status:                'sent',
          fcm_message_id:        response.messageId,
          sent_at:               new Date(),
        });
      } else {
        stats.failed++;
        await Notification.create({
          id:                    uuidv4(),
          user_id:               notif.userId,
          batch_id:              notif.batchId || null,
          fee_id:                notif.feeId   || null,
          type:                  notif.type,
          fcm_payload:           notif.payload,
          device_token_snapshot: notif.deviceToken,
          status:                'failed',
          error_message:         response.error?.message || 'FCM batch error',
        });

        await handleStaleToken(response.error, notif.userId);
      }
    })
  );

  return stats;
}

// ─── Stale Token Handler ──────────────────────────────────────────────────────

/**
 * handleStaleToken
 * Clears the FCM token for a user when FCM reports it as invalid.
 * PRD Section 11: "handle FCM 410 errors to deregister stale tokens"
 *
 * @param {Error|Object} error - FCM error
 * @param {string} userId
 */
async function handleStaleToken(error, userId) {
  const staleTokenCodes = [
    'messaging/registration-token-not-registered',
    'messaging/invalid-registration-token',
    'messaging/invalid-argument',
  ];

  const errorCode = error?.code || error?.errorInfo?.code || '';

  if (staleTokenCodes.some((code) => errorCode.includes(code))) {
    try {
      await User.update({ fcm_token: null }, { where: { id: userId } });
      logger.warn(`Cleared stale FCM token for user ${userId} (error: ${errorCode})`);
    } catch (updateError) {
      logger.error(`Failed to clear FCM token for user ${userId}:`, updateError);
    }
  }
}

// ─── Convenience Wrappers ─────────────────────────────────────────────────────

/**
 * notifyFeeOverdue
 * Sends a fee_overdue notification to a specific student.
 */
async function notifyFeeOverdue({ student, batchId, batchName, month, amountDue, feeId }) {
  if (!student.fcm_token) {
    logger.warn(`Cannot notify student ${student.id} — no FCM token`);
    return { success: false };
  }

  const payload = buildFeeOverduePayload({ batchId, batchName, month, amountDue, feeId });

  return sendNotification({
    userId:      student.id,
    batchId,
    feeId,
    type:        'fee_overdue',
    payload,
    deviceToken: student.fcm_token,
  });
}

/**
 * notifyFeePaid
 * Sends a fee_paid confirmation notification to a student.
 */
async function notifyFeePaid({ student, batchId, batchName, month, amountPaid, feeId }) {
  if (!student.fcm_token) return { success: false };

  const payload = buildFeePaidPayload({ batchId, batchName, month, amountPaid, feeId });

  return sendNotification({
    userId:      student.id,
    batchId,
    feeId,
    type:        'fee_paid',
    payload,
    deviceToken: student.fcm_token,
  });
}

/**
 * notifyFileShared
 * Sends a file_shared notification to all batch members.
 */
async function notifyFileShared({ recipients, batchId, batchName, fileRecordId, originalName, uploaderName }) {
  const payload = buildFileSharedPayload({
    batchId,
    batchName,
    fileRecordId,
    originalName,
    uploaderName,
  });

  const notifications = recipients
    .filter((r) => r.fcm_token)
    .map((r) => ({
      userId:      r.id,
      batchId,
      feeId:       null,
      type:        'file_shared',
      payload,
      deviceToken: r.fcm_token,
    }));

  return sendBatchNotifications(notifications);
}

module.exports = {
  sendNotification,
  sendBatchNotifications,
  notifyFeeOverdue,
  notifyFeePaid,
  notifyFileShared,
  buildFeeOverduePayload,
  buildFeePaidPayload,
  buildFileSharedPayload,
};