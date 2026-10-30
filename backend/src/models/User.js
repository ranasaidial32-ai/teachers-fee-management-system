/**
 * models/User.js
 * Added: avatar_id (1–5), name is now updatable via PUT /auth/profile
 */

'use strict';

const { DataTypes } = require('sequelize');

module.exports = function UserModel(sequelize) {
  const User = sequelize.define(
    'User',
    {
      id: {
        type: DataTypes.UUID,
        defaultValue: DataTypes.UUIDV4,
        primaryKey: true,
        allowNull: false,
        comment: 'UUID v4 primary key',
      },

      name: {
        type: DataTypes.STRING(120),
        allowNull: false,
        validate: {
          notEmpty: { msg: 'Name cannot be blank' },
          len: { args: [2, 120], msg: 'Name must be between 2 and 120 characters' },
        },
      },

      email: {
        type: DataTypes.STRING(255),
        allowNull: false,
        unique: {
          name: 'users_email_unique',
          msg: 'An account with this email already exists',
        },
        validate: {
          isEmail: { msg: 'Must be a valid email address' },
        },
      },

      password_hash: {
        type: DataTypes.STRING(255),
        allowNull: false,
        comment: 'bcrypt hash, 12 rounds',
      },

      role: {
        type: DataTypes.ENUM('teacher', 'student'),
        allowNull: false,
        defaultValue: 'student',
        comment: 'teacher = admin, student = user (PRD Section 02)',
      },

      fcm_token: {
        type: DataTypes.TEXT,
        allowNull: true,
        defaultValue: null,
        comment: 'Latest FCM registration token; null if not registered',
      },

      // ── NEW: Avatar ID ──────────────────────────────────────────────────────
      // Integer 1–5 maps to one of the 5 preset avatar images.
      // Stored as a tiny integer — no file uploads, no R2 storage needed.
      // Chat bubbles and profile page read this to render the correct avatar.
      // NULL = user hasn't chosen an avatar yet → show initial letter fallback.
      avatar_id: {
        type: DataTypes.TINYINT,
        allowNull: true,
        defaultValue: null,
        validate: {
          min: { args: [1], msg: 'avatar_id must be between 1 and 5' },
          max: { args: [5], msg: 'avatar_id must be between 1 and 5' },
        },
        comment: 'Preset avatar index 1–5; null = show letter initial fallback',
      },

      is_active: {
        type: DataTypes.BOOLEAN,
        allowNull: false,
        defaultValue: true,
        comment: 'False = soft-deleted or suspended account',
      },
    },
    {
      tableName: 'users',
      timestamps: true,
      underscored: true,

      indexes: [
        { unique: true, fields: ['email'], name: 'idx_users_email' },
        { fields: ['role'],      name: 'idx_users_role'      },
        { fields: ['avatar_id'], name: 'idx_users_avatar_id' },
      ],
    }
  );

  return User;
};