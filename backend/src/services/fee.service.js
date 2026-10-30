/**
 * services/fee.service.js
 * Business logic layer for fee management operations.
 *
 * PRD Reference: Section 04 — Batch & Fee Management — Detailed Specs
 *
 * Separates fee business logic from the HTTP controller layer.
 * Used by:
 *  - fee.controller.js (REST API)
 *  - feeOverdue.cron.js (scheduled job)
 *  - billingCycle.cron.js (monthly reset)
 *
 * RESPONSIBILITIES:
 *  - Create fee records for new billing cycles
 *  - Detect and mark overdue fees
 *  - Provide fee summary aggregations
 *  - Reset fee statuses for new cycles
 */

'use strict';

const { Op }          = require('sequelize');
const { v4: uuidv4 }  = require('uuid');
const { Fee, Batch, User, Enrollment, sequelize } = require('../models/index');
const logger          = require('../config/logger');

/**
 * getCurrentBillingMonth
 * @returns {string} YYYY-MM
 */
function getCurrentBillingMonth() {
  const now   = new Date();
  const year  = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  return `${year}-${month}`;
}

/**
 * createFeeRecord
 * Creates a single fee record for a student in a batch for a billing month.
 * Idempotent via findOrCreate.
 *
 * @param {Object} params
 * @param {string} params.batchId
 * @param {string} params.studentId
 * @param {number} params.amountDue
 * @param {string} params.billingMonth - YYYY-MM
 * @returns {Promise<{ fee: Object, created: boolean }>}
 */
async function createFeeRecord({ batchId, studentId, amountDue, billingMonth }) {
  const [fee, created] = await Fee.findOrCreate({
    where: {
      batch_id:      batchId,
      student_id:    studentId,
      billing_month: billingMonth,
    },
    defaults: {
      id:            uuidv4(),
      batch_id:      batchId,
      student_id:    studentId,
      billing_month: billingMonth,
      amount_due:    amountDue,
      status:        'pending',
    },
  });

  return { fee, created };
}

/**
 * createFeesForBatch
 * Creates fee records for ALL active students in a batch for a given month.
 * Used by billing cycle cron and when a new batch is created mid-month.
 *
 * @param {string} batchId
 * @param {string} billingMonth - YYYY-MM (defaults to current month)
 * @returns {Promise<{ created: number, skipped: number }>}
 */
async function createFeesForBatch(batchId, billingMonth = getCurrentBillingMonth()) {
  const batch = await Batch.findOne({
    where: { id: batchId, is_active: true },
    attributes: ['id', 'fee_amount'],
  });

  if (!batch) throw new Error(`Batch ${batchId} not found`);

  const enrollments = await Enrollment.findAll({
    where: { batch_id: batchId, is_active: true },
    attributes: ['student_id'],
  });

  let created = 0;
  let skipped = 0;

  for (const enrollment of enrollments) {
    const { created: wasCreated } = await createFeeRecord({
      batchId,
      studentId:    enrollment.student_id,
      amountDue:    batch.fee_amount,
      billingMonth,
    });

    wasCreated ? created++ : skipped++;
  }

  logger.info(
    `createFeesForBatch: batch=${batchId} month=${billingMonth} ` +
    `created=${created} skipped=${skipped}`
  );

  return { created, skipped };
}

/**
 * markFeeOverdue
 * Transitions a fee from 'pending' to 'overdue'.
 * Called by the fee overdue cron job.
 *
 * @param {string[]} feeIds
 * @returns {Promise<number>} Number of rows updated
 */
async function markFeeOverdue(feeIds) {
  if (!feeIds || feeIds.length === 0) return 0;

  const [affectedRows] = await Fee.update(
    { status: 'overdue' },
    {
      where: {
        id:     { [Op.in]: feeIds },
        status: 'pending', // Only transition from pending
      },
    }
  );

  return affectedRows;
}

/**
 * markFeePaid
 * Transitions a fee to 'paid' status with audit trail.
 * Validates teacher ownership before update.
 *
 * @param {string} feeId
 * @param {string} teacherId
 * @returns {Promise<Object>} Updated fee object
 * @throws {Error} If fee not found or teacher doesn't own the batch
 */
async function markFeePaid(feeId, teacherId) {
  const fee = await Fee.findOne({
    where: { id: feeId },
    include: [
      {
        model: Batch,
        as: 'batch',
        attributes: ['teacher_id', 'name'],
      },
    ],
  });

  if (!fee) throw Object.assign(new Error('Fee not found.'), { status: 404 });

  if (fee.batch.teacher_id !== teacherId) {
    throw Object.assign(
      new Error('You are not authorised to mark this fee as paid.'),
      { status: 403 }
    );
  }

  if (fee.status === 'paid') {
    throw Object.assign(
      new Error(`Fee already paid at ${fee.paid_at?.toISOString()}`),
      { status: 409 }
    );
  }

  await fee.update({
    status:         'paid',
    paid_at:        new Date(),
    marked_paid_by: teacherId,
  });

  return fee;
}

/**
 * getFeeSummaryForBatch
 * Returns aggregated fee stats for a batch for a given month.
 *
 * @param {string} batchId
 * @param {string} billingMonth - YYYY-MM
 * @returns {Promise<{ total: number, paid: number, pending: number, overdue: number, collection_rate: string }>}
 */
async function getFeeSummaryForBatch(batchId, billingMonth = getCurrentBillingMonth()) {
  const fees = await Fee.findAll({
    where: { batch_id: batchId, billing_month: billingMonth },
    attributes: ['status', 'amount_due'],
  });

  const total   = fees.length;
  const paid    = fees.filter((f) => f.status === 'paid').length;
  const pending = fees.filter((f) => f.status === 'pending').length;
  const overdue = fees.filter((f) => f.status === 'overdue').length;

  const totalRevenue    = fees
    .filter((f) => f.status === 'paid')
    .reduce((sum, f) => sum + f.amount_due, 0);

  const expectedRevenue = fees.reduce((sum, f) => sum + f.amount_due, 0);

  const collectionRate = total > 0
    ? ((paid / total) * 100).toFixed(1)
    : '0.0';

  return {
    billing_month:     billingMonth,
    total,
    paid,
    pending,
    overdue,
    collection_rate:   `${collectionRate}%`,
    total_revenue:     totalRevenue,
    expected_revenue:  expectedRevenue,
    outstanding:       expectedRevenue - totalRevenue,
  };
}

/**
 * getStudentFeeSummary
 * Returns a student's fee status across all their enrolled batches
 * for the current billing month.
 *
 * @param {string} studentId
 * @returns {Promise<Object>}
 */
async function getStudentFeeSummary(studentId) {
  const billingMonth = getCurrentBillingMonth();

  const fees = await Fee.findAll({
    where: {
      student_id:    studentId,
      billing_month: billingMonth,
    },
    include: [
      {
        model: Batch,
        as: 'batch',
        attributes: ['id', 'name'],
      },
    ],
    attributes: ['id', 'status', 'amount_due', 'paid_at'],
  });

  const totalDue = fees
    .filter((f) => f.status !== 'paid')
    .reduce((sum, f) => sum + f.amount_due, 0);

  return {
    billing_month: billingMonth,
    fees,
    summary: {
      total:     fees.length,
      paid:      fees.filter((f) => f.status === 'paid').length,
      pending:   fees.filter((f) => f.status === 'pending').length,
      overdue:   fees.filter((f) => f.status === 'overdue').length,
      total_due: totalDue,
    },
  };
}

module.exports = {
  getCurrentBillingMonth,
  createFeeRecord,
  createFeesForBatch,
  markFeeOverdue,
  markFeePaid,
  getFeeSummaryForBatch,
  getStudentFeeSummary,
};