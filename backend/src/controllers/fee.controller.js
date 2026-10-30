/**
 * controllers/fee.controller.js
 * Manages fee status retrieval and manual payment marking.
 *
 * PRD Reference: Section 04 — Fee Lifecycle & Payment Status States
 * PRD Reference: Section 09 — Fee API Endpoints
 *   GET /fees/:batchId        Get fee statuses for batch (teacher)
 *   PUT /fees/mark-paid       Mark student fee as paid (teacher)
 *   GET /fees/student/:id     Student fee history
 *   GET /fees/my-fees         Student's own fees across all batches
 *
 * FEE STATUS TRANSITIONS:
 *  pending → paid    (teacher marks paid)
 *  pending → overdue (cron job when grace period expires)
 *  overdue → paid    (teacher marks paid even after overdue)
 *  paid    → pending (auto-reset on next billing cycle by cron)
 *
 * BILLING CYCLE RESET:
 *  The cron job (feeOverdue.cron.js) handles creating new fee records
 *  at the start of each month. This controller handles reading and
 *  updating existing records only.
 */

'use strict';

const { Op }  = require('sequelize');
const { Fee, Batch, User, Enrollment, Notification } = require('../models/index');
const { v4: uuidv4 } = require('uuid');
const logger = require('../config/logger');

// ─── Controller Methods ───────────────────────────────────────────────────────

/**
 * getBatchFees
 * GET /fees/:batchId
 * Teacher only — get all students' fee statuses for a batch in a given month.
 *
 * Query params:
 *  month (optional) — billing month in YYYY-MM format (defaults to current month)
 */
async function getBatchFees(req, res) {
  try {
    const { batchId } = req.params;
    const billingMonth = req.query.month || getCurrentBillingMonth();

    // Validate month format
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(billingMonth)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid month format. Use YYYY-MM (e.g., "2025-06").',
      });
    }

    // Verify teacher owns this batch
    const batch = await Batch.findOne({
      where: { id: batchId, teacher_id: req.user.id },
      attributes: ['id', 'name', 'fee_amount', 'grace_period_days'],
    });

    if (!batch) {
      return res.status(404).json({
        success: false,
        message: 'Batch not found or you do not own it.',
      });
    }

    // Fetch fee records with student details
    const fees = await Fee.findAll({
      where: { batch_id: batchId, billing_month: billingMonth },
      include: [
        {
          model: User,
          as: 'student',
          attributes: ['id', 'name', 'email'],
        },
      ],
      order: [['created_at', 'ASC']],
    });

    // Summary counts
    const summary = {
      total:   fees.length,
      paid:    fees.filter((f) => f.status === 'paid').length,
      pending: fees.filter((f) => f.status === 'pending').length,
      overdue: fees.filter((f) => f.status === 'overdue').length,
    };

    return res.status(200).json({
      success: true,
      data: {
        batch,
        billing_month: billingMonth,
        summary,
        fees,
      },
    });
  } catch (error) {
    logger.error('getBatchFees error:', error);
    return res.status(500).json({ success: false, message: 'Failed to fetch fee records.' });
  }
}

/**
 * markPaid
 * PUT /fees/mark-paid
 * Teacher only — manually marks a student's fee as paid.
 *
 * PRD Section 04: "Teacher marks payment as Paid manually"
 *
 * Body: { fee_id }
 */
async function markPaid(req, res) {
  try {
    const { fee_id } = req.body;

    // Fetch the fee record with batch info to verify teacher ownership
    const fee = await Fee.findOne({
      where: { id: fee_id },
      include: [
        {
          model: Batch,
          as: 'batch',
          attributes: ['id', 'name', 'teacher_id'],
        },
        {
          model: User,
          as: 'student',
          attributes: ['id', 'name', 'email', 'fcm_token'],
        },
      ],
    });

    if (!fee) {
      return res.status(404).json({ success: false, message: 'Fee record not found.' });
    }

    // RBAC: Only the batch's teacher can mark fees as paid
    if (fee.batch.teacher_id !== req.user.id) {
      return res.status(403).json({
        success: false,
        message: 'You can only mark fees for your own batches.',
      });
    }

    // Idempotency: already paid
    if (fee.status === 'paid') {
      return res.status(409).json({
        success: false,
        message: `Fee is already marked as paid (paid at: ${fee.paid_at?.toISOString()}).`,
      });
    }

    // Mark as paid
    await fee.update({
      status:         'paid',
      paid_at:        new Date(),
      marked_paid_by: req.user.id,
    });

    // Log notification record (fee_paid type)
    await Notification.create({
      id:         uuidv4(),
      user_id:    fee.student_id,
      batch_id:   fee.batch_id,
      fee_id:     fee.id,
      type:       'fee_paid',
      fcm_payload: {
        type:        'fee_paid',
        batch_id:    fee.batch_id,
        batch_name:  fee.batch.name,
        month:       fee.billing_month,
        amount_paid: String(fee.amount_due),
      },
      status: 'queued', // Will be dispatched separately if needed
    });

    logger.info(
      `Fee ${fee_id} marked PAID by teacher ${req.user.id} ` +
      `for student ${fee.student_id} in batch ${fee.batch_id}`
    );

    return res.status(200).json({
      success: true,
      message: `Fee marked as paid for ${fee.student.name}.`,
      data: { fee },
    });
  } catch (error) {
    logger.error('markPaid error:', error);
    return res.status(500).json({ success: false, message: 'Failed to mark fee as paid.' });
  }
}

/**
 * getStudentFeeHistory
 * GET /fees/student/:id
 * Teacher only — view a specific student's fee history across all
 * batches taught by this teacher.
 *
 * Query params:
 *  batch_id (optional) — filter by specific batch
 *  limit    (optional) — default 12 (last 12 months)
 *  page     (optional) — pagination
 */
async function getStudentFeeHistory(req, res) {
  try {
    const { id: studentId } = req.params;
    const { batch_id, page = 1, limit = 12 } = req.query;

    const offset = (parseInt(page, 10) - 1) * parseInt(limit, 10);

    // Build where clause
    const whereClause = { student_id: studentId };
    if (batch_id) whereClause.batch_id = batch_id;

    const { rows: fees, count: total } = await Fee.findAndCountAll({
      where: whereClause,
      include: [
        {
          model: Batch,
          as: 'batch',
          attributes: ['id', 'name', 'fee_amount', 'teacher_id'],
          // Ensure teacher can only see fees from their own batches
          where: { teacher_id: req.user.id },
        },
        {
          model: User,
          as: 'student',
          attributes: ['id', 'name', 'email'],
        },
      ],
      order:  [['billing_month', 'DESC']],
      limit:  parseInt(limit, 10),
      offset,
    });

    return res.status(200).json({
      success: true,
      data: {
        fees,
        pagination: {
          total,
          page:       parseInt(page, 10),
          limit:      parseInt(limit, 10),
          totalPages: Math.ceil(total / parseInt(limit, 10)),
        },
      },
    });
  } catch (error) {
    logger.error('getStudentFeeHistory error:', error);
    return res.status(500).json({ success: false, message: 'Failed to fetch fee history.' });
  }
}

/**
 * getMyFees
 * GET /fees/my-fees
 * Student only — view own fee status across all enrolled batches.
 *
 * PRD Section 02: "View payment status & history"
 *
 * Query params:
 *  month (optional) — filter by billing month (YYYY-MM)
 *  page, limit      — pagination
 */
async function getMyFees(req, res) {
  try {
    const { month, page = 1, limit = 12 } = req.query;
    const offset = (parseInt(page, 10) - 1) * parseInt(limit, 10);

    const whereClause = { student_id: req.user.id };
    if (month) whereClause.billing_month = month;

    const { rows: fees, count: total } = await Fee.findAndCountAll({
      where: whereClause,
      include: [
        {
          model: Batch,
          as: 'batch',
          attributes: ['id', 'name', 'fee_amount', 'grace_period_days'],
          include: [
            {
              model: User,
              as: 'teacher',
              attributes: ['id', 'name'],
            },
          ],
        },
      ],
      order:  [['billing_month', 'DESC']],
      limit:  parseInt(limit, 10),
      offset,
    });

    // Current month summary
    const currentMonth = getCurrentBillingMonth();
    const currentMonthFees = fees.filter((f) => f.billing_month === currentMonth);

    return res.status(200).json({
      success: true,
      data: {
        current_month: currentMonth,
        current_month_summary: {
          total:   currentMonthFees.length,
          paid:    currentMonthFees.filter((f) => f.status === 'paid').length,
          pending: currentMonthFees.filter((f) => f.status === 'pending').length,
          overdue: currentMonthFees.filter((f) => f.status === 'overdue').length,
          total_due: currentMonthFees
            .filter((f) => f.status !== 'paid')
            .reduce((sum, f) => sum + f.amount_due, 0),
        },
        fees,
        pagination: {
          total,
          page:       parseInt(page, 10),
          limit:      parseInt(limit, 10),
          totalPages: Math.ceil(total / parseInt(limit, 10)),
        },
      },
    });
  } catch (error) {
    logger.error('getMyFees error:', error);
    return res.status(500).json({ success: false, message: 'Failed to fetch your fees.' });
  }
}

// ─── Local Helpers ────────────────────────────────────────────────────────────

function getCurrentBillingMonth() {
  const now   = new Date();
  const year  = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  return `${year}-${month}`;
}

module.exports = { getBatchFees, markPaid, getStudentFeeHistory, getMyFees };