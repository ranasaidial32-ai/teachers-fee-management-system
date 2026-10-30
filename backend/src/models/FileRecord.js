/**
 * models/FileRecord.js
 * Tracks files uploaded to Cloudflare R2 via the chat system.
 *
 * PRD Reference: Section 07 — File Storage Architecture
 *
 * FILE LIFECYCLE (PRD Section 07):
 *  1. Teacher uploads file → Node.js streams to R2
 *  2. Signed URL generated → broadcast via Socket.IO
 *  3. Flutter WorkManager auto-downloads on student devices
 *  4. Cron job runs 12h after upload → deletes from R2
 *  5. Students view from local cache; server copy gone
 *
 * FIELDS
 *  r2_key          The object key in R2 bucket (used for deletion)
 *  r2_bucket       Bucket name (allows multi-bucket future migration)
 *  original_name   Original filename shown in UI
 *  mime_type       MIME type for correct Content-Type on download
 *  size_bytes      File size (enforced ≤ 25 MB per PRD Section 11)
 *  signed_url      Pre-signed URL valid for R2_SIGNED_URL_EXPIRES seconds
 *  signed_url_expires_at  When the signed URL expires
 *  upload_expires_at      When the cron job will delete the R2 object (12h)
 *  is_deleted_from_r2     True after cron deletes the object from R2
 *  deleted_from_r2_at     Timestamp of R2 deletion
 */

'use strict';

const { DataTypes } = require('sequelize');

module.exports = function FileRecordModel(sequelize) {
  const FileRecord = sequelize.define(
    'FileRecord',
    {
      id: {
        type: DataTypes.UUID,
        defaultValue: DataTypes.UUIDV4,
        primaryKey: true,
        allowNull: false,
      },

      // FK → messages.id (the chat message this file was sent through)
      message_id: {
        type: DataTypes.UUID,
        allowNull: true,          // null for direct uploads outside chat
        defaultValue: null,
        references: { model: 'messages', key: 'id' },
        onDelete: 'SET NULL',
      },

      // Who uploaded this file (for RBAC checks on deletion)
      uploader_id: {
        type: DataTypes.UUID,
        allowNull: false,
        references: { model: 'users', key: 'id' },
        onDelete: 'CASCADE',
      },

      // Cloudflare R2 object key — e.g. "batches/B_001/files/uuid-filename.pdf"
      r2_key: {
        type: DataTypes.STRING(500),
        allowNull: false,
        unique: { name: 'idx_filerecords_r2_key', msg: 'R2 key must be unique' },
        comment: 'S3-compatible object key in Cloudflare R2 bucket',
      },

      r2_bucket: {
        type: DataTypes.STRING(100),
        allowNull: false,
        comment: 'R2 bucket name (from R2_BUCKET_NAME env var)',
      },

      original_name: {
        type: DataTypes.STRING(255),
        allowNull: false,
        comment: 'Original filename as uploaded by user',
      },

      mime_type: {
        type: DataTypes.STRING(100),
        allowNull: false,
        defaultValue: 'application/octet-stream',
      },

      size_bytes: {
        type: DataTypes.INTEGER.UNSIGNED,
        allowNull: false,
        validate: {
          max: {
            args: [26214400], // 25 MB in bytes (PRD Section 11)
            msg: 'File size cannot exceed 25 MB',
          },
        },
      },

      // Pre-signed URL for client download
      signed_url: {
        type: DataTypes.TEXT,
        allowNull: false,
        comment: 'Short-lived signed URL for R2 object access (PRD Section 10)',
      },

      signed_url_expires_at: {
        type: DataTypes.DATE,
        allowNull: false,
        comment: 'When the signed URL expires (R2_SIGNED_URL_EXPIRES seconds from upload)',
      },

      // 12h server-side deletion timer (PRD Section 07)
      upload_expires_at: {
        type: DataTypes.DATE,
        allowNull: false,
        comment: 'When cron will delete this file from R2 (upload_time + 12h)',
      },

      is_deleted_from_r2: {
        type: DataTypes.BOOLEAN,
        allowNull: false,
        defaultValue: false,
        comment: 'True after cron job deletes the object from R2',
      },

      deleted_from_r2_at: {
        type: DataTypes.DATE,
        allowNull: true,
        defaultValue: null,
      },
    },
    {
      tableName: 'file_records',
      timestamps: true,
      underscored: true,

      indexes: [
        // Cron query: find all files where upload_expires_at <= NOW and not yet deleted
        {
          fields: ['upload_expires_at', 'is_deleted_from_r2'],
          name: 'idx_filerecords_cron_cleanup',
        },

        // Look up files by message
        { fields: ['message_id'], name: 'idx_filerecords_message_id' },

        // Uploader audit
        { fields: ['uploader_id'], name: 'idx_filerecords_uploader_id' },
      ],
    }
  );

  return FileRecord;
};