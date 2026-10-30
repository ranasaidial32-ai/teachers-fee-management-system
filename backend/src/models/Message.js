/**
 * models/Message.js
 * Represents a single chat message within a batch group chat.
 *
 * PRD Reference: Section 06 — Encrypted Group Chat
 *
 * SUPPORTED MESSAGE TYPES (PRD Section 06):
 *  text    — plain text message
 *  image   — JPEG, PNG, WEBP image (stored in R2)
 *  file    — PDF, DOCX, XLSX, ZIP (stored in R2)
 *  folder  — ZIP archive of a folder (stored in R2)
 *  voice   — AAC / OGG voice recording (stored in R2)
 *
 * E2EE NOTE:
 *  The `content` field stores the *encrypted ciphertext* of the message.
 *  Encryption/decryption happens client-side via the Signal Protocol
 *  Flutter implementation. The server stores and relays ciphertext only —
 *  it never has access to plaintext (true E2EE).
 *
 * For file/image/voice/folder messages, `content` holds encrypted
 * metadata JSON (filename, size, mime_type, signed_url) and the
 * associated FileRecord row holds R2 storage details.
 *
 * PERMISSIONS (PRD Section 06):
 *  - Both teacher and student can send any message type
 *  - Only teacher (admin) can delete any message
 *  - Students can only delete their own messages (not implemented in MVP)
 */

'use strict';

const { DataTypes } = require('sequelize');

module.exports = function MessageModel(sequelize) {
  const Message = sequelize.define(
    'Message',
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
        comment: 'Which batch chat this message belongs to',
      },

      sender_id: {
        type: DataTypes.UUID,
        allowNull: false,
        references: { model: 'users', key: 'id' },
        onDelete: 'CASCADE',
        comment: 'FK → users.id (message author)',
      },

      type: {
        type: DataTypes.ENUM('text', 'image', 'file', 'folder', 'voice'),
        allowNull: false,
        defaultValue: 'text',
        comment: 'Message content type (PRD Section 06 — Supported Message Types)',
      },

      // Stores encrypted ciphertext (Signal Protocol)
      // For text: encrypted plaintext
      // For media: encrypted JSON metadata { filename, size, mime_type }
      content: {
        type: DataTypes.TEXT('long'),
        allowNull: false,
        comment: 'E2EE ciphertext — server never sees plaintext (PRD Section 06)',
      },

      // Signal Protocol: sender ratchet public key (for recipient decryption)
      // Stored as base64 string
      signal_message_key: {
        type: DataTypes.TEXT,
        allowNull: true,
        defaultValue: null,
        comment: 'Signal Protocol ephemeral key material for E2EE',
      },

      is_deleted: {
        type: DataTypes.BOOLEAN,
        allowNull: false,
        defaultValue: false,
        comment: 'Soft delete — teacher can delete any message (PRD Section 06)',
      },

      deleted_at: {
        type: DataTypes.DATE,
        allowNull: true,
        defaultValue: null,
      },

      deleted_by: {
        type: DataTypes.UUID,
        allowNull: true,
        defaultValue: null,
        references: { model: 'users', key: 'id' },
        comment: 'FK → users.id of who deleted the message (teacher only)',
      },
    },
    {
      tableName: 'messages',
      timestamps: true,
      underscored: true,

      indexes: [
        // Paginated message history for a batch chat (PRD Section 09)
        {
          fields: ['batch_id', 'created_at'],
          name: 'idx_messages_batch_timeline',
        },

        // Sender's message list
        { fields: ['sender_id'], name: 'idx_messages_sender_id' },

        // Filter deleted messages
        { fields: ['is_deleted'], name: 'idx_messages_is_deleted' },
      ],
    }
  );

  return Message;
};