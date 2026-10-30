/**
 * models/Batch.js
 * Represents a teaching batch created by a teacher.
 *
 * PRD Reference: Section 04 — Batch & Fee Management — Detailed Specs
 *
 * FIELDS
 *  id                UUID primary key
 *  teacher_id        FK → users.id (creator)
 *  name              Batch display name (e.g., "Class 10 Science")
 *  start_date        Date the billing cycle originated
 *  fee_amount        Monthly fee in INR (integer, no decimals for simplicity)
 *  duration_years    How long the batch runs (integer years)
 *  grace_period_days Number of days after billing cycle start before
 *                    overdue notification fires (PRD: "Fees Time Limit")
 *  is_active         Whether batch is currently running
 *  created_at / updated_at — auto-managed
 */

'use strict';

const { DataTypes } = require('sequelize');

module.exports = function BatchModel(sequelize) {
  const Batch = sequelize.define(
    'Batch',
    {
      id: {
        type: DataTypes.UUID,
        defaultValue: DataTypes.UUIDV4,
        primaryKey: true,
        allowNull: false,
      },

      teacher_id: {
        type: DataTypes.UUID,
        allowNull: false,
        references: { model: 'users', key: 'id' },
        onDelete: 'CASCADE',
        comment: 'FK → users.id (teacher who created this batch)',
      },

      name: {
        type: DataTypes.STRING(150),
        allowNull: false,
        validate: {
          notEmpty: { msg: 'Batch name cannot be blank' },
          len: { args: [2, 150], msg: 'Batch name must be 2–150 characters' },
        },
      },

      start_date: {
        type: DataTypes.DATEONLY,
        allowNull: false,
        comment: 'The date from which the billing cycle is calculated',
      },

      fee_amount: {
        type: DataTypes.INTEGER.UNSIGNED,
        allowNull: false,
        validate: {
          min: { args: [1], msg: 'Fee amount must be at least ₹1' },
          max: { args: [999999], msg: 'Fee amount too large' },
        },
        comment: 'Monthly fee in INR (integer rupees)',
      },

      duration_years: {
        type: DataTypes.TINYINT.UNSIGNED,
        allowNull: false,
        defaultValue: 1,
        validate: {
          min: { args: [1], msg: 'Duration must be at least 1 year' },
          max: { args: [10], msg: 'Duration cannot exceed 10 years' },
        },
      },

      grace_period_days: {
        type: DataTypes.TINYINT.UNSIGNED,
        allowNull: false,
        defaultValue: 7,
        validate: {
          min: { args: [1], msg: 'Grace period must be at least 1 day' },
          max: { args: [28], msg: 'Grace period cannot exceed 28 days' },
        },
        comment:
          'Days after billing cycle start before overdue FCM notification fires (PRD Section 04)',
      },

      is_active: {
        type: DataTypes.BOOLEAN,
        allowNull: false,
        defaultValue: true,
      },
    },
    {
      tableName: 'batches',
      timestamps: true,
      underscored: true,

      indexes: [
        // Teacher's batch list
        { fields: ['teacher_id'], name: 'idx_batches_teacher_id' },

        // Cron job: query batches where billing_start + grace_period matches today
        { fields: ['start_date', 'grace_period_days'], name: 'idx_batches_cron' },

        // Active batch filter
        { fields: ['is_active'], name: 'idx_batches_is_active' },
      ],
    }
  );

  return Batch;
};