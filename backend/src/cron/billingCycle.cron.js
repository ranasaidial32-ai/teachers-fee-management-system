/**
 * cron/billingCycle.cron.js
 * Monthly cron job that creates new fee records at the start of each
 * billing cycle for all active enrollments.
 *
 * PRD Reference: Section 04 — Fee Lifecycle
 *   "Status auto-resets on next billing cycle; process repeats"
 *   "Billing cycle begins (start of month)"
 *
 * WHEN IT RUNS:
 *   00:05 UTC on the 1st of every month ("5 0 1 * *")
 *   The 5-minute offset avoids collision with the daily fee overdue
 *   cron which runs at 00:01.
 *
 * WHAT IT DOES:
 *   For every active Enrollment:
 *     1. Snapshot the current batch.fee_amount
 *     2. Create a new Fee record with status='pending' for the new month
 *     3. Use findOrCreate for idempotency (safe to re-run)
 *
 * IMPORTANT:
 *   This job does NOT reset existing fee records — it creates NEW ones.
 *   Historical fee records are preserved permanently for audit trail.
 *
 * REGISTRATION IN app.js:
 *   This cron is NOT started automatically from app.js in the current setup.
 *   Add startBillingCycleCron() to app.js alongside the other cron starts:
 *
 *   const { startBillingCycleCron } = require('./cron/billingCycle.cron');
 *   startBillingCycleCron();
 */

'use strict';

const cron   = require('node-cron');
const { v4: uuidv4 } = require('uuid');

const { Enrollment, Batch, Fee } = require('../models/index');
const logger = require('../config/logger');

/**
 * runBillingCycle
 * Creates fee records for the new billing month.
 *
 * @param {Date} [targetDate] - Override date (for testing). Defaults to now.
 * @returns {Promise<{ created: number, skipped: number, failed: number }>}
 */
async function runBillingCycle(targetDate = new Date()) {
  const startTime = Date.now();
  logger.info('═══ Billing Cycle Cron: Starting run ═══');

  const stats = { created: 0, skipped: 0, failed: 0 };

  try {
    const year  = targetDate.getFullYear();
    const month = String(targetDate.getMonth() + 1).padStart(2, '0');
    const billingMonth = `${year}-${month}`;

    logger.info(`Creating fee records for billing month: ${billingMonth}`);

    // Fetch all active enrollments with their batch fee amount
    const activeEnrollments = await Enrollment.findAll({
      where: { is_active: true },
      include: [
        {
          model: Batch,
          as: 'batch',
          where: { is_active: true },
          attributes: ['id', 'fee_amount', 'name'],
        },
      ],
      attributes: ['id', 'batch_id', 'student_id'],
    });

    logger.info(`Processing ${activeEnrollments.length} active enrollment(s)`);

    // Process in batches of 50 to avoid memory spikes
    const chunkSize = 50;
    for (let i = 0; i < activeEnrollments.length; i += chunkSize) {
      const chunk = activeEnrollments.slice(i, i + chunkSize);

      await Promise.allSettled(
        chunk.map(async (enrollment) => {
          try {
            const [, created] = await Fee.findOrCreate({
              where: {
                batch_id:      enrollment.batch_id,
                student_id:    enrollment.student_id,
                billing_month: billingMonth,
              },
              defaults: {
                id:            uuidv4(),
                batch_id:      enrollment.batch_id,
                student_id:    enrollment.student_id,
                billing_month: billingMonth,
                amount_due:    enrollment.batch.fee_amount,
                status:        'pending',
              },
            });

            if (created) {
              stats.created++;
              logger.debug(
                `Fee record created: batch=${enrollment.batch_id} ` +
                `student=${enrollment.student_id} month=${billingMonth}`
              );
            } else {
              stats.skipped++;
              logger.debug(
                `Fee record already exists: batch=${enrollment.batch_id} ` +
                `student=${enrollment.student_id} month=${billingMonth}`
              );
            }
          } catch (rowError) {
            stats.failed++;
            logger.error(
              `Failed to create fee for enrollment ${enrollment.id}:`,
              rowError.message
            );
          }
        })
      );
    }

    const duration = Date.now() - startTime;
    logger.info(
      `═══ Billing Cycle Cron Complete ═══\n` +
      `  Created:  ${stats.created}\n` +
      `  Skipped:  ${stats.skipped} (already existed)\n` +
      `  Failed:   ${stats.failed}\n` +
      `  Duration: ${duration}ms`
    );

    return stats;

  } catch (error) {
    logger.error('Billing cycle cron encountered a fatal error:', error);
    throw error;
  }
}

/**
 * startBillingCycleCron
 * Schedules the monthly billing cycle job.
 */
function startBillingCycleCron() {
  // 00:05 UTC on 1st of every month
  const schedule = '5 0 1 * *';

  const job = cron.schedule(
    schedule,
    async () => {
      try {
        await runBillingCycle();
      } catch (err) {
        logger.error('Billing cycle cron job failed:', err);
      }
    },
    {
      timezone:  'UTC',
      scheduled: true,
    }
  );

  logger.info(`✅  Billing cycle cron scheduled: "${schedule}" — 1st of every month at 00:05 UTC`);
  return job;
}

module.exports = { startBillingCycleCron, runBillingCycle };