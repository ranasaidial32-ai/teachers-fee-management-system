/**
 * models/Notification.js
 * Audit log of every FCM notification dispatched by the system.
 *
 * PRD Reference: Section 05 — Notification System
 *   "Log notification event in DB with timestamp & delivery status"
 *
 * NOTIFICATION TYPES:
 *  fee_overdue  — Grace period expired without payment
 *  fee_paid     — Teacher marked fee as paid (optional confirmation)
 *  file_shared  — Teacher shared a new file in batch chat
 *  chat_message — New message in batch chat (future: per-user opt-in)
 *
 * DELIVERY STATUS:
 *  queued     — Added to dispatch queue, not yet sent
 *  sent       — FCM API accepted the message (does not confirm device receipt)
 *  failed     — FCM returned an error (token invalid, quota exceeded, etc.)
 *  delivered  — Device acknowledged receipt (FCM delivery receipt if enabled)
 *
 * WHY STORE THIS:
 *  - Audit trail for ≥90% delivery rate success metric (PRD Section 01)
 *  - Enables retry logic for failed notifications
 *  - Allows teacher to see when student was last notified
 */

'use strict';

const { DataTypes } = require('sequelize');

module.exports = function NotificationModel(sequelize) {
  const Notification = sequelize.define(
    'Notification',
    {
      id: {
        type: DataTypes.UUID,
        defaultValue: DataTypes.UUIDV4,
        primaryKey: true,
        allowNull: false,
      },

      // Recipient of the notification
      user_id: {
        type: DataTypes.UUID,
        allowNull: false,
        references: { model: 'users', key: 'id' },
        onDelete: 'CASCADE',
      },

      // Optional: which batch triggered this notification
      batch_id: {
        type: DataTypes.UUID,
        allowNull: true,
        defaultValue: null,
        references: { model: 'batches', key: 'id' },
        onDelete: 'SET NULL',
      },

      // Optional: which fee record triggered this notification
      fee_id: {
        type: DataTypes.UUID,
        allowNull: true,
        defaultValue: null,
        references: { model: 'fees', key: 'id' },
        onDelete: 'SET NULL',
      },

      type: {
        type: DataTypes.ENUM('fee_overdue', 'fee_paid', 'file_shared', 'chat_message'),
        allowNull: false,
        comment: 'Notification category for client-side routing',
      },

      // The FCM data payload that was sent (stored as JSON string)
      // Stored for debugging and retry purposes
      fcm_payload: {
        type: DataTypes.JSON,
        allowNull: false,
        comment: 'FCM data payload object sent to Firebase (no PII — PRD Section 10)',
      },

      // Device token used for this dispatch attempt
      device_token_snapshot: {
        type: DataTypes.TEXT,
        allowNull: true,
        comment: 'FCM token at time of dispatch (for stale token detection)',
      },

      status: {
        type: DataTypes.ENUM('queued', 'sent', 'failed', 'delivered'),
        allowNull: false,
        defaultValue: 'queued',
      },

      // FCM message ID returned by Firebase on success
      fcm_message_id: {
        type: DataTypes.STRING(255),
        allowNull: true,
        defaultValue: null,
        comment: 'Firebase message ID — null if dispatch failed',
      },

      // Error message if FCM returned an error
      error_message: {
        type: DataTypes.TEXT,
        allowNull: true,
        defaultValue: null,
      },

      // When the notification was dispatched to FCM
      sent_at: {
        type: DataTypes.DATE,
        allowNull: true,
        defaultValue: null,
      },
    },
    {
      tableName: 'notifications',
      timestamps: true,
      underscored: true,

      indexes: [
        // User notification history
        {
          fields: ['user_id', 'created_at'],
          name: 'idx_notifications_user_timeline',
        },

        // Retry failed notifications
        { fields: ['status'], name: 'idx_notifications_status' },

        // Batch notification overview for teacher
        { fields: ['batch_id', 'type'], name: 'idx_notifications_batch_type' },

        // Fee-level audit
        { fields: ['fee_id'], name: 'idx_notifications_fee_id' },
      ],
    }
  );

  return Notification;
};