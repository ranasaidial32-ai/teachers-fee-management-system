/**
 * controllers/notification.controller.js
 * REST endpoints for notification history and management.
 *
 * These endpoints allow:
 *  - Students to view their notification history
 *  - Teachers to view notification delivery stats for their batches
 *  - System to query failed notifications for retry
 *
 * PRD Reference: Section 05 — Notification System
 *   "Log notification event in DB with timestamp & delivery status"
 *   "≥90% notification delivery rate" (success metric)
 */

'use strict';

const { Op }          = require('sequelize');
const { Notification, Batch, Fee, User } = require('../models/index');
const logger          = require('../config/logger');

/**
 * getMyNotifications
 * GET /notifications/my
 * Student — returns paginated notification history for the authenticated user.
 *
 * Query params:
 *  type   (optional) — filter by type ('fee_overdue', 'fee_paid', etc.)
 *  page   (optional) — default 1
 *  limit  (optional) — default 20, max 50
 */
async function getMyNotifications(req, res) {
  try {
    const { type, page = 1, limit = 20 } = req.query;
    const offset = (parseInt(page, 10) - 1) * parseInt(limit, 10);

    const whereClause = { user_id: req.user.id };
    if (type) whereClause.type = type;

    const { rows: notifications, count: total } = await Notification.findAndCountAll({
      where: whereClause,
      attributes: [
        'id', 'type', 'fcm_payload', 'status',
        'sent_at', 'created_at', 'batch_id',
      ],
      include: [
        {
          model: Batch,
          as: 'batch',   // Note: association uses batch_id, alias set in index.js
          required: false,
          attributes: ['id', 'name'],
        },
      ],
      order:  [['created_at', 'DESC']],
      limit:  parseInt(limit, 10),
      offset,
    });

    // Count unread (sent but not acknowledged by client — simple: all sent)
    const unreadCount = await Notification.count({
      where: {
        user_id: req.user.id,
        status:  'sent',
      },
    });

    return res.status(200).json({
      success: true,
      data: {
        notifications,
        unread_count: unreadCount,
        pagination: {
          total,
          page:       parseInt(page, 10),
          limit:      parseInt(limit, 10),
          totalPages: Math.ceil(total / parseInt(limit, 10)),
        },
      },
    });
  } catch (error) {
    logger.error('getMyNotifications error:', error);
    return res.status(500).json({ success: false, message: 'Failed to fetch notifications.' });
  }
}

/**
 * getBatchNotificationStats
 * GET /notifications/batch/:batchId/stats
 * Teacher only — delivery stats for a batch (for the ≥90% metric).
 *
 * Query params:
 *  month (optional) — billing month in YYYY-MM format
 */
async function getBatchNotificationStats(req, res) {
  try {
    const { batchId } = req.params;
    const { month }   = req.query;

    // Verify teacher owns this batch
    const batch = await Batch.findOne({
      where: { id: batchId, teacher_id: req.user.id },
      attributes: ['id', 'name'],
    });

    if (!batch) {
      return res.status(404).json({
        success: false,
        message: 'Batch not found or you do not own it.',
      });
    }

    const whereClause = { batch_id: batchId };
    if (month) {
      // Filter notifications for fees in that billing month
      // Join with fees to filter by billing_month
      whereClause['$fee.billing_month$'] = month;
    }

    const notifications = await Notification.findAll({
      where: whereClause,
      include: [
        {
          model: Fee,
          as: 'fee',
          required: false,
          attributes: ['billing_month', 'status'],
        },
        {
          model: User,
          as: 'user',
          attributes: ['id', 'name'],
        },
      ],
      attributes: ['id', 'type', 'status', 'sent_at', 'error_message', 'created_at'],
      order: [['created_at', 'DESC']],
    });

    // Compute delivery rate stats
    const total     = notifications.length;
    const sent      = notifications.filter((n) => n.status === 'sent').length;
    const failed    = notifications.filter((n) => n.status === 'failed').length;
    const queued    = notifications.filter((n) => n.status === 'queued').length;
    const rate      = total > 0 ? ((sent / total) * 100).toFixed(1) : '0.0';

    // Group by type
    const byType = notifications.reduce((acc, n) => {
      acc[n.type] = (acc[n.type] || 0) + 1;
      return acc;
    }, {});

    return res.status(200).json({
      success: true,
      data: {
        batch: { id: batch.id, name: batch.name },
        stats: {
          total,
          sent,
          failed,
          queued,
          delivery_rate_percent: rate,
          meets_prd_target:      parseFloat(rate) >= 90,
          by_type:               byType,
        },
        notifications,
      },
    });
  } catch (error) {
    logger.error('getBatchNotificationStats error:', error);
    return res.status(500).json({ success: false, message: 'Failed to fetch notification stats.' });
  }
}

/**
 * getFailedNotifications
 * GET /notifications/failed
 * Teacher only — list failed notifications that need attention.
 *
 * Query params:
 *  batch_id (optional) — filter by batch
 *  limit    (optional) — default 50
 */
async function getFailedNotifications(req, res) {
  try {
    const { batch_id, limit = 50 } = req.query;

    const whereClause = { status: 'failed' };
    if (batch_id) whereClause.batch_id = batch_id;

    const failed = await Notification.findAll({
      where: whereClause,
      include: [
        {
          model: Batch,
          as: 'batch',
          required: false,
          where: batch_id ? undefined : { teacher_id: req.user.id },
          attributes: ['id', 'name', 'teacher_id'],
        },
        {
          model: User,
          as: 'user',
          attributes: ['id', 'name', 'fcm_token'],
        },
      ],
      order:  [['created_at', 'DESC']],
      limit:  parseInt(limit, 10),
    });

    // Filter to only show notifications from teacher's own batches
    const ownedFailed = failed.filter((n) => {
      if (!n.batch) return false;
      return n.batch.teacher_id === req.user.id;
    });

    return res.status(200).json({
      success: true,
      data: { failed_notifications: ownedFailed, count: ownedFailed.length },
    });
  } catch (error) {
    logger.error('getFailedNotifications error:', error);
    return res.status(500).json({ success: false, message: 'Failed to fetch failed notifications.' });
  }
}

module.exports = {
  getMyNotifications,
  getBatchNotificationStats,
  getFailedNotifications,
};