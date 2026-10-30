/**
 * models/MessageDelivery.js
 * Tracks per-student message delivery and read status.
 *
 * LOGIC:
 *  - Created when a message is saved (one row per enrolled student)
 *  - downloaded_at set when student's device ACKs receipt
 *  - read_at set when student opens/views the message
 *  - When downloaded_count / total_students >= 0.99 → message auto-deleted
 */

'use strict';

const { DataTypes } = require('sequelize');

module.exports = function MessageDeliveryModel(sequelize) {
  const MessageDelivery = sequelize.define(
    'MessageDelivery',
    {
      id: {
        type: DataTypes.UUID,
        defaultValue: DataTypes.UUIDV4,
        primaryKey: true,
        allowNull: false,
      },

      message_id: {
        type: DataTypes.UUID,
        allowNull: false,
        references: { model: 'messages', key: 'id' },
        onDelete: 'CASCADE',
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

      // Set when Flutter client emits 'message_delivered' ACK
      downloaded_at: {
        type: DataTypes.DATE,
        allowNull: true,
        defaultValue: null,
        comment: 'When student device confirmed receipt/download',
      },

      // Set when student opens chat and sees the message
      read_at: {
        type: DataTypes.DATE,
        allowNull: true,
        defaultValue: null,
        comment: 'When student viewed the message in chat',
      },
    },
    {
      tableName: 'message_deliveries',
      timestamps: true,
      underscored: true,

      indexes: [
        {
          unique: true,
          fields: ['message_id', 'student_id'],
          name: 'idx_delivery_unique_pair',
        },
        { fields: ['message_id'], name: 'idx_delivery_message_id' },
        { fields: ['batch_id'],   name: 'idx_delivery_batch_id'   },
        { fields: ['student_id'], name: 'idx_delivery_student_id' },
        { fields: ['downloaded_at'], name: 'idx_delivery_downloaded' },
        { fields: ['read_at'],    name: 'idx_delivery_read_at'    },
      ],
    }
  );

  return MessageDelivery;
};