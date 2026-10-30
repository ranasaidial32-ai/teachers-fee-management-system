/**
 * models/RefreshToken.js
 * Stores JWT refresh tokens for multi-device support and rotation.
 *
 * PRD Reference: Section 10 — Security & Compliance
 *   "JWT tokens expire in 15 min"
 *   "Device token rotation on each login"
 *
 * ROTATION STRATEGY:
 *  On every /auth/refresh call:
 *   1. Validate the incoming refresh token exists in DB and is not revoked
 *   2. Issue a new access token (15min) + new refresh token (7d)
 *   3. Revoke the old refresh token (set is_revoked = true)
 *  This implements refresh token rotation — a compromised token can only
 *  be used once before it is invalidated.
 *
 *  On logout: set is_revoked = true for the user's current refresh token.
 *  On new login: old tokens for that device are revoked (one active token per device).
 *
 * MULTIPLE DEVICES:
 *  Each login from a different device creates a new row, keyed by device_id.
 *  This allows a teacher to be logged in on phone + tablet simultaneously.
 */

'use strict';

const { DataTypes } = require('sequelize');

module.exports = function RefreshTokenModel(sequelize) {
  const RefreshToken = sequelize.define(
    'RefreshToken',
    {
      id: {
        type: DataTypes.UUID,
        defaultValue: DataTypes.UUIDV4,
        primaryKey: true,
        allowNull: false,
      },

      user_id: {
        type: DataTypes.UUID,
        allowNull: false,
        references: { model: 'users', key: 'id' },
        onDelete: 'CASCADE',
      },

      // The hashed refresh token value (never store plaintext tokens in DB)
      token_hash: {
        type: DataTypes.STRING(255),
        allowNull: false,
        comment: 'bcrypt hash of the refresh token string',
      },

      // Optional: identifies the device/client for multi-device management
      // Flutter app sends a unique device ID (e.g., flutter_udid package)
      device_id: {
        type: DataTypes.STRING(255),
        allowNull: true,
        defaultValue: null,
        comment: 'Client device identifier for per-device token management',
      },

      // IP address at time of login (for security audit)
      issued_ip: {
        type: DataTypes.STRING(45),  // 45 chars covers IPv6
        allowNull: true,
        defaultValue: null,
      },

      expires_at: {
        type: DataTypes.DATE,
        allowNull: false,
        comment: 'Token expiry (JWT_REFRESH_EXPIRES_IN from env)',
      },

      is_revoked: {
        type: DataTypes.BOOLEAN,
        allowNull: false,
        defaultValue: false,
        comment: 'True after logout or token rotation',
      },

      revoked_at: {
        type: DataTypes.DATE,
        allowNull: true,
        defaultValue: null,
      },
    },
    {
      tableName: 'refresh_tokens',
      timestamps: true,
      underscored: true,

      indexes: [
        // Fast lookup by user (list all active sessions)
        { fields: ['user_id', 'is_revoked'], name: 'idx_refresh_tokens_user_active' },

        // Per-device token lookup (revoke old token on new login from same device)
        {
          fields: ['user_id', 'device_id'],
          name: 'idx_refresh_tokens_user_device',
        },

        // Cleanup expired tokens (nightly cron)
        { fields: ['expires_at', 'is_revoked'], name: 'idx_refresh_tokens_expiry' },
      ],
    }
  );

  return RefreshToken;
};