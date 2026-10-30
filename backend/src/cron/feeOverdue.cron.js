/**
 * cron/feeOverdue.cron.js
 * Daily cron job that detects overdue fees and dispatches FCM notifications.
 *
 * PRD Reference: Section 05 — Notification System — Trigger Logic
 *   "Node.js cron job runs daily at 00:01 UTC"
 *   "Query all batches where current date = (billing_start + grace_period_days)"
 *   "For each matching batch, filter students with payment_status = 'pending'"
 *   "Send FCM data payload to each student's registered device token"
 *   "Log notification event in DB with timestamp & delivery status"
 *
 * PRD Reference: Section 05 — FCM Payload Example
 *   {
 *     "type": "fee_overdue",
 *     "batch_id": "B_001",
 *     "batch_name": "Class 10 Science",
 *     "month": "June 2025",
 *     "amount_due": "1500"
 *   }
 *
 * CRON SCHEDULE:
 *   Default: "1 0 * * *" — 00:01 UTC daily
 *   Configurable via FEE_CRON_SCHEDULE env var
 *
 * OVERDUE DETECTION LOGIC:
 *   A fee is overdue when:
 *   current day of month >= grace_period_days
 *   AND billing_month = current month
 *   AND status = 'pending'
 *
 *   Note: The PRD says "billing_start + grace_period_days".
 *   Since billing always starts on day 1 of the month:
 *   overdue_date = day grace_period_days of current month
 *   e.g., grace_period_days=9 → overdue from day 9 onwards
 *
 * FCM DELIVERY:
 *   Uses sendFCMBatch() to send up to 500 notifications per FCM API call.
 *   Students without FCM tokens are skipped (logged as warning).
 *   FCM 410 errors (invalid token) trigger token cleanup.
 *
 * NOTIFICATION DEDUPLICATION:
 *   Checks notification_sent_at on Fee record to prevent sending
 *   duplicate notifications for the same billing cycle.
 */

'use strict';

const cron   = require('node-cron');
const { Op } = require('sequelize');
const { v4: uuidv4 } = require('uuid');

const { Fee, Batch, User, Enrollment, Notification } = require('../models/index');
const { sendFCMBatch }  = require('../config/firebase');
const logger            = require('../config/logger');

/**
 * runFeeOverdueCheck
 * Core logic — separated from cron wrapper for testability.
 * Can be called manually for backfill or testing.
 *
 * @returns {Promise<{ processed: number, notified: number, skipped: number, failed: number }>}
 */
async function runFeeOverdueCheck() {
  const startTime = Date.now();
  logger.info('═══ Fee Overdue Cron: Starting run ═══');

  const stats = { processed: 0, notified: 0, skipped: 0, failed: 0 };

  try {
    const now          = new Date();
    const currentDay   = now.getDate();
    const currentYear  = now.getFullYear();
    const currentMonth = String(now.getMonth() + 1).padStart(2, '0');
    const billingMonth = `${currentYear}-${currentMonth}`;

    logger.info(`Checking overdue fees for billing month: ${billingMonth}, day: ${currentDay}`);

    // ── Step 1: Find all active batches where today >= grace_period_days ──────
    // These are batches whose grace period has expired today or earlier
    const eligibleBatches = await Batch.findAll({
      where: {
        is_active:          true,
        grace_period_days:  { [Op.lte]: currentDay }, // grace period has passed
      },
      attributes: ['id', 'name', 'fee_amount', 'grace_period_days', 'teacher_id'],
    });

    logger.info(`Found ${eligibleBatches.length} batches with expired grace periods`);

    if (eligibleBatches.length === 0) {
      logger.info('No eligible batches found. Cron complete.');
      return stats;
    }

    const batchIds = eligibleBatches.map((b) => b.id);

    // ── Step 2: Find pending fees for these batches in current billing month ──
    // Only fees that haven't had a notification sent yet (deduplication)
    const pendingFees = await Fee.findAll({
      where: {
        batch_id:            { [Op.in]: batchIds },
        billing_month:       billingMonth,
        status:              'pending',
        notification_sent_at: null, // Not yet notified this cycle
      },
      include: [
        {
          model: User,
          as: 'student',
          attributes: ['id', 'name', 'fcm_token'],
          where: { is_active: true },
        },
        {
          model: Batch,
          as: 'batch',
          attributes: ['id', 'name', 'fee_amount'],
        },
      ],
    });

    logger.info(`Found ${pendingFees.length} pending fees to process`);
    stats.processed = pendingFees.length;

    if (pendingFees.length === 0) {
      logger.info('No pending fees require notification. Cron complete.');
      return stats;
    }

    // ── Step 3: Update fee status to 'overdue' ────────────────────────────────
    const feeIds = pendingFees.map((f) => f.id);
    await Fee.update(
      { status: 'overdue' },
      { where: { id: { [Op.in]: feeIds } } }
    );
    logger.info(`Marked ${feeIds.length} fees as overdue`);

    // ── Step 4: Build FCM message batch ───────────────────────────────────────
    const fcmMessages       = [];
    const notificationRows  = [];
    const skippedFees       = [];

    // Format billing month for display: "2025-06" → "June 2025"
    const monthDisplay = formatBillingMonth(billingMonth);

    for (const fee of pendingFees) {
      const student = fee.student;

      // Skip students without FCM tokens (not logged into app yet)
      if (!student.fcm_token) {
        logger.warn(`Student ${student.id} has no FCM token — skipping notification`);
        stats.skipped++;
        skippedFees.push(fee.id);
        continue;
      }

      // Build FCM payload per PRD Section 05
      const fcmPayload = {
        type:        'fee_overdue',
        batch_id:    fee.batch_id,
        batch_name:  fee.batch.name,
        month:       monthDisplay,
        amount_due:  String(fee.amount_due),
        fee_id:      fee.id,
      };

      fcmMessages.push({
        token: student.fcm_token,
        data:  fcmPayload,
      });

      // Prepare notification log row
      notificationRows.push({
        id:                     uuidv4(),
        user_id:                student.id,
        batch_id:               fee.batch_id,
        fee_id:                 fee.id,
        type:                   'fee_overdue',
        fcm_payload:            fcmPayload,
        device_token_snapshot:  student.fcm_token,
        status:                 'queued',
        sent_at:                null,
      });
    }

    // ── Step 5: Send FCM batch (max 500 per call) ─────────────────────────────
    if (fcmMessages.length === 0) {
      logger.info('No FCM messages to send (all students lack tokens).');
      return stats;
    }

    // Split into chunks of 500 (FCM batch limit)
    const chunks = chunkArray(fcmMessages, 500);
    const notifChunks = chunkArray(notificationRows, 500);

    for (let i = 0; i < chunks.length; i++) {
      const chunk      = chunks[i];
      const notifChunk = notifChunks[i];

      logger.info(`Sending FCM batch ${i + 1}/${chunks.length} (${chunk.length} messages)`);

      try {
        const batchResponse = await sendFCMBatch(chunk);

        // Process individual results
        batchResponse.responses.forEach((response, index) => {
          const notifRow = notifChunk[index];
          const fee      = pendingFees.find((f) => f.id === notifRow.fee_id);

          if (response.success) {
            notifRow.status       = 'sent';
            notifRow.sent_at      = new Date();
            notifRow.fcm_message_id = response.messageId;
            stats.notified++;

            // Update fee.notification_sent_at to prevent re-notification
            if (fee) {
              fee.notification_sent_at = new Date(); // Staged for bulk update below
            }
          } else {
            notifRow.status        = 'failed';
            notifRow.error_message = response.error?.message || 'Unknown FCM error';
            stats.failed++;

            logger.warn(
              `FCM send failed for notification ${notifRow.id}: ${notifRow.error_message}`
            );

            // Handle stale/invalid FCM tokens (PRD Section 11)
            if (
              response.error?.code === 'messaging/registration-token-not-registered' ||
              response.error?.code === 'messaging/invalid-registration-token'
            ) {
              // Deregister stale token asynchronously (non-blocking)
              User.update(
                { fcm_token: null },
                { where: { id: notifRow.user_id } }
              ).catch((err) =>
                logger.error(`Failed to clear stale FCM token for user ${notifRow.user_id}:`, err)
              );
            }
          }
        });

      } catch (batchError) {
        logger.error(`FCM batch ${i + 1} failed entirely:`, batchError);
        notifChunk.forEach((n) => {
          n.status        = 'failed';
          n.error_message = batchError.message;
          stats.failed++;
        });
      }

      // ── Step 6: Bulk insert notification logs ──────────────────────────────
      await Notification.bulkCreate(notifChunk, { ignoreDuplicates: true });
    }

    // ── Step 7: Bulk update fee.notification_sent_at ──────────────────────────
    const notifiedFeeIds = pendingFees
      .filter((f) => f.notification_sent_at)
      .map((f) => f.id);

    if (notifiedFeeIds.length > 0) {
      await Fee.update(
        { notification_sent_at: new Date() },
        { where: { id: { [Op.in]: notifiedFeeIds } } }
      );
    }

    const duration = Date.now() - startTime;
    logger.info(
      `═══ Fee Overdue Cron Complete ═══\n` +
      `  Processed: ${stats.processed}\n` +
      `  Notified:  ${stats.notified}\n` +
      `  Skipped:   ${stats.skipped} (no FCM token)\n` +
      `  Failed:    ${stats.failed}\n` +
      `  Duration:  ${duration}ms`
    );

    return stats;

  } catch (error) {
    logger.error('Fee overdue cron encountered a fatal error:', error);
    throw error;
  }
}

/**
 * startFeeOverdueCron
 * Registers the cron schedule. Called from app.js.
 */
function startFeeOverdueCron() {
  const schedule = process.env.FEE_CRON_SCHEDULE || '1 0 * * *';

  if (!cron.validate(schedule)) {
    logger.error(`Invalid FEE_CRON_SCHEDULE: "${schedule}". Using default "1 0 * * *".`);
  }

  const job = cron.schedule(
    schedule,
    async () => {
      try {
        await runFeeOverdueCheck();
      } catch (err) {
        logger.error('Fee overdue cron job failed:', err);
        // Do not throw — cron must continue running
      }
    },
    {
      timezone:  'UTC',
      scheduled: true,
    }
  );

  logger.info(`✅  Fee overdue cron scheduled: "${schedule}" (UTC)`);
  return job;
}

// ─── Utility Functions ────────────────────────────────────────────────────────

/**
 * formatBillingMonth
 * Converts "2025-06" to "June 2025" for human-readable notification display.
 *
 * @param {string} billingMonth - YYYY-MM format
 * @returns {string}
 */
function formatBillingMonth(billingMonth) {
  const [year, month] = billingMonth.split('-');
  const date = new Date(parseInt(year, 10), parseInt(month, 10) - 1, 1);
  return date.toLocaleDateString('en-IN', { month: 'long', year: 'numeric' });
}

/**
 * chunkArray
 * Splits an array into chunks of specified size.
 *
 * @param {Array} arr
 * @param {number} size
 * @returns {Array[]}
 */
function chunkArray(arr, size) {
  const chunks = [];
  for (let i = 0; i < arr.length; i += size) {
    chunks.push(arr.slice(i, i + size));
  }
  return chunks;
}

module.exports = { startFeeOverdueCron, runFeeOverdueCheck };