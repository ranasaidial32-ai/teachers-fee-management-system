/**
 * models/Fee.js
 * Tracks monthly fee payment status per student per batch per billing cycle.
 *
 * PRD Reference: Section 04 — Fee Lifecycle & Payment Status States
 *
 * FEE LIFECYCLE (as per PRD):
 *  1. Billing cycle begins (start of month)
 *  2. Grace period runs (N days set by teacher)
 *  3. If unpaid after grace period → status = 'overdue', FCM sent
 *  4. Teacher marks payment as 'paid' manually
 *  5. Status auto-resets on next billing cycle
 *
 * PAYMENT STATUS STATES (PRD Section 04):
 *  pending  — not yet paid, within grace period
 *  overdue  — grace period expired, unpaid
 *  paid     — marked paid by teacher
 *
 * One row is created per student per batch per billing_month.
 * The cron job creates new rows at the start of each calendar month
 * for all active enrollments.
 */

'use strict';

const { DataTypes } = require('sequelize');

module.exports = function FeeModel(sequelize) {
  const Fee = sequelize.define(
    'Fee',
    {
      id: {
        type: DataTypes.UUID,
        defaultValue: DataTypes.UUIDV4,
        primaryKey: true,
        allowNull: false,
      },

      batch_id: {
        type: DataTypes.UUID,
        allowNull: false,
        references: { model: 'batches', key: 'id' },
        onDelete: 'CASCADE',
      },

      student_id: {
        type: DataTypes.UUID,
        allowNull: false,
        references: { model: 'users', key: 'id' },
        onDelete: 'CASCADE',
      },

      // "2025-06" format — uniquely identifies the billing month
      billing_month: {
        type: DataTypes.STRING(7),
        allowNull: false,
        comment: 'Billing month in YYYY-MM format (e.g., "2025-06")',
        validate: {
          is: {
            args: /^\d{4}-(0[1-9]|1[0-2])$/,
            msg: 'billing_month must be in YYYY-MM format',
          },
        },
      },

      amount_due: {
        type: DataTypes.INTEGER.UNSIGNED,
        allowNull: false,
        comment: 'Snapshot of batch fee_amount at time of cycle creation',
      },

      status: {
        type: DataTypes.ENUM('pending', 'overdue', 'paid'),
        allowNull: false,
        defaultValue: 'pending',
        comment: 'Fee payment status (PRD Section 04)',
      },

      // Null until teacher marks as paid
      paid_at: {
        type: DataTypes.DATE,
        allowNull: true,
        defaultValue: null,
      },

      // Null until FCM notification is dispatched
      notification_sent_at: {
        type: DataTypes.DATE,
        allowNull: true,
        defaultValue: null,
        comment: 'Timestamp when overdue FCM was dispatched; null if not yet sent',
      },

      // Teacher who marked the payment (audit trail)
      marked_paid_by: {
        type: DataTypes.UUID,
        allowNull: true,
        defaultValue: null,
        references: { model: 'users', key: 'id' },
        comment: 'FK → users.id of teacher who marked paid',
      },
    },
    {
      tableName: 'fees',
      timestamps: true,
      underscored: true,

      indexes: [
        // Prevent duplicate fee records for same student/batch/month
        {
          unique: true,
          fields: ['batch_id', 'student_id', 'billing_month'],
          name: 'idx_fees_unique_cycle',
        },

        // Cron: find all pending/overdue fees for a given month
        { fields: ['billing_month', 'status'], name: 'idx_fees_cron_check' },

        // Student fee history page
        { fields: ['student_id', 'billing_month'], name: 'idx_fees_student_history' },

        // Batch fee overview for teacher
        { fields: ['batch_id', 'status'], name: 'idx_fees_batch_status' },
      ],
    }
  );

  return Fee;
};