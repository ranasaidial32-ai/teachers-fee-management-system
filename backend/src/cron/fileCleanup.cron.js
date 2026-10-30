/**
 * cron/fileCleanup.cron.js
 * Cron job that deletes files from Cloudflare R2 12 hours after upload.
 *
 * PRD Reference: Section 07 — File Storage Architecture
 *   "Cron job runs 12h after upload; deletes file from R2
 *    (lifecycle policy or manual deletion API call)"
 *   "Students continue to view the file from local storage;
 *    server copy no longer exists"
 *
 * SCHEDULE:
 *   Runs every 30 minutes to catch files within ~30 minutes of their
 *   12-hour expiry window. This provides a reasonable cleanup latency
 *   without hammering the R2 API.
 *
 * DELETION LOGIC:
 *   Query FileRecord WHERE upload_expires_at <= NOW AND is_deleted_from_r2 = false
 *   For each record:
 *     1. Call R2 DeleteObjectCommand
 *     2. Update FileRecord: is_deleted_from_r2=true, deleted_from_r2_at=NOW
 *     3. Log result
 *
 * IDEMPOTENCY:
 *   The is_deleted_from_r2 flag prevents double-deletion attempts.
 *   R2 DeleteObject is also idempotent (deleting a non-existent key
 *   returns success) so double-calls are safe anyway.
 *
 * ERROR HANDLING:
 *   Individual file deletion failures are logged but don't stop the batch.
 *   Failed files will be retried on the next cron run.
 */

'use strict';

const cron   = require('node-cron');
const { Op } = require('sequelize');
const {
  S3Client,
  DeleteObjectCommand,
} = require('@aws-sdk/client-s3');

const { FileRecord } = require('../models/index');
const logger         = require('../config/logger');

/**
 * getR2Client
 * Creates Cloudflare R2 S3-compatible client.
 * Imported here to avoid circular dependency with file.controller.js.
 */
function getR2Client() {
  return new S3Client({
    region:   'auto',
    endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId:     process.env.R2_ACCESS_KEY_ID,
      secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
    },
  });
}

/**
 * runFileCleanup
 * Core cleanup logic — separated for testability.
 *
 * @returns {Promise<{ deleted: number, failed: number, skipped: number }>}
 */
async function runFileCleanup() {
  const startTime = Date.now();
  logger.info('═══ File Cleanup Cron: Starting run ═══');

  const stats = { deleted: 0, failed: 0, skipped: 0 };

  try {
    // Find all expired, not-yet-deleted file records
    const expiredFiles = await FileRecord.findAll({
      where: {
        upload_expires_at:   { [Op.lte]: new Date() },
        is_deleted_from_r2:  false,
      },
      attributes: [
        'id',
        'r2_key',
        'r2_bucket',
        'original_name',
        'upload_expires_at',
        'uploader_id',
      ],
      order: [['upload_expires_at', 'ASC']], // Delete oldest first
      limit: 200,  // Process at most 200 per run to avoid timeout
    });

    logger.info(`Found ${expiredFiles.length} expired file(s) to delete from R2`);

    if (expiredFiles.length === 0) {
      logger.info('No expired files. Cleanup cron complete.');
      return stats;
    }

    const r2Client = getR2Client();

    // Process deletions with concurrency limit of 10 parallel requests
    // to avoid overwhelming R2 API or exhausting Node.js event loop
    const concurrencyLimit = 10;
    const chunks = [];
    for (let i = 0; i < expiredFiles.length; i += concurrencyLimit) {
      chunks.push(expiredFiles.slice(i, i + concurrencyLimit));
    }

    for (const chunk of chunks) {
      await Promise.allSettled(
        chunk.map(async (fileRecord) => {
          try {
            // Attempt R2 deletion
            const deleteCommand = new DeleteObjectCommand({
              Bucket: fileRecord.r2_bucket,
              Key:    fileRecord.r2_key,
            });

            await r2Client.send(deleteCommand);

            // Mark as deleted in DB
            await fileRecord.update({
              is_deleted_from_r2:  true,
              deleted_from_r2_at:  new Date(),
            });

            stats.deleted++;
            logger.debug(
              `Deleted from R2: ${fileRecord.r2_key} ` +
              `(expired: ${fileRecord.upload_expires_at.toISOString()})`
            );

          } catch (deleteError) {
            stats.failed++;
            logger.error(
              `Failed to delete R2 object ${fileRecord.r2_key}: ${deleteError.message}`
            );
            // Do not update is_deleted_from_r2 — will retry next cron run
          }
        })
      );
    }

    const duration = Date.now() - startTime;
    logger.info(
      `═══ File Cleanup Cron Complete ═══\n` +
      `  Deleted: ${stats.deleted}\n` +
      `  Failed:  ${stats.failed} (will retry)\n` +
      `  Duration: ${duration}ms`
    );

    return stats;

  } catch (error) {
    logger.error('File cleanup cron encountered a fatal error:', error);
    throw error;
  }
}

/**
 * startFileCleanupCron
 * Registers the cleanup cron schedule.
 * Called from app.js.
 */
function startFileCleanupCron() {
  // Run every 30 minutes
  const schedule = '*/30 * * * *';

  const job = cron.schedule(
    schedule,
    async () => {
      try {
        await runFileCleanup();
      } catch (err) {
        logger.error('File cleanup cron job failed:', err);
        // Do not throw — cron must keep running
      }
    },
    {
      timezone:  'UTC',
      scheduled: true,
    }
  );

  logger.info(`✅  File cleanup cron scheduled: "${schedule}" — every 30 minutes (UTC)`);
  return job;
}

module.exports = { startFileCleanupCron, runFileCleanup };