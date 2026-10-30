/**
 * controllers/auth.controller.js
 * Handles all authentication flows for EduPay.
 *
 * PRD Reference: Section 09 — Auth API Endpoints
 *   POST /auth/register  — Register teacher or student
 *   POST /auth/login     — Login, returns JWT + refresh token
 *   POST /auth/refresh   — Refresh access token
 *   POST /auth/logout    — Revoke refresh token (added for completeness)
 *
 * PRD Reference: Section 10 — Security & Compliance
 *   JWT tokens expire in 15 min
 *   Passwords hashed with bcrypt (12 rounds)
 *   Device token rotation on each login
 *   Refresh token rotation on every /auth/refresh call
 *
 * FLOW:
 *  Register → hash password → create User → return tokens
 *  Login    → verify password → update FCM token → rotate refresh token → return tokens
 *  Refresh  → verify refresh token hash → rotate → return new tokens
 *  Logout   → revoke refresh token for this device
 */

/**
 * controllers/auth.controller.js
 * Added: updateProfile — PUT /auth/profile
 *        Updates name and/or avatar_id for the authenticated user.
 *        getMe now returns avatar_id.
 */

'use strict';

const bcrypt  = require('bcrypt');
const jwt     = require('jsonwebtoken');
const crypto  = require('crypto');
const { v4: uuidv4 } = require('uuid');
const { Op }  = require('sequelize');

const { User, RefreshToken } = require('../models/index');
const logger = require('../config/logger');

// ─── Token Helpers ────────────────────────────────────────────────────────────

function generateAccessToken(user) {
  return jwt.sign(
    { id: user.id, role: user.role },
    process.env.JWT_ACCESS_SECRET,
    {
      expiresIn: process.env.JWT_ACCESS_EXPIRES_IN || '15m',
      issuer:    'edupay-api',
      audience:  'edupay-client',
    }
  );
}

async function generateRefreshToken() {
  const raw = crypto.randomBytes(64).toString('hex');
  const BCRYPT_ROUNDS = parseInt(process.env.BCRYPT_ROUNDS, 10) || 12;
  const hash = await bcrypt.hash(raw, BCRYPT_ROUNDS);
  const expiresInStr = process.env.JWT_REFRESH_EXPIRES_IN || '7d';
  const expiresAt = parseExpiryString(expiresInStr);
  return { raw, hash, expiresAt };
}

function parseExpiryString(str) {
  const unit  = str.slice(-1);
  const value = parseInt(str.slice(0, -1), 10);
  const ms = {
    d: value * 24 * 60 * 60 * 1000,
    h: value * 60 * 60 * 1000,
    m: value * 60 * 1000,
    s: value * 1000,
  }[unit] || 7 * 24 * 60 * 60 * 1000;
  return new Date(Date.now() + ms);
}

async function issueTokenPair(user, deviceId, clientIp) {
  const accessToken = generateAccessToken(user);
  const { raw: refreshTokenRaw, hash: refreshTokenHash, expiresAt } =
    await generateRefreshToken();

  if (deviceId) {
    await RefreshToken.update(
      { is_revoked: true, revoked_at: new Date() },
      {
        where: {
          user_id:    user.id,
          device_id:  deviceId,
          is_revoked: false,
        },
      }
    );
  }

  await RefreshToken.create({
    id:          uuidv4(),
    user_id:     user.id,
    token_hash:  refreshTokenHash,
    device_id:   deviceId || null,
    issued_ip:   clientIp || null,
    expires_at:  expiresAt,
    is_revoked:  false,
  });

  return { accessToken, refreshToken: refreshTokenRaw, expiresAt };
}

// ─── Shared user serialiser ───────────────────────────────────────────────────
// Single place that defines what user fields we return to clients.
// All endpoints use this so avatar_id is never forgotten.
function serializeUser(user) {
  return {
    id:        user.id,
    name:      user.name,
    email:     user.email,
    role:      user.role,
    avatar_id: user.avatar_id ?? null,
  };
}

// ─── Controller Methods ───────────────────────────────────────────────────────

async function register(req, res) {
  try {
    const { name, email, password, role } = req.body;

    const existing = await User.findOne({ where: { email } });
    if (existing) {
      return res.status(409).json({
        success: false,
        message: 'An account with this email address already exists.',
      });
    }

    const BCRYPT_ROUNDS = parseInt(process.env.BCRYPT_ROUNDS, 10) || 12;
    const password_hash = await bcrypt.hash(password, BCRYPT_ROUNDS);

    const user = await User.create({
      id:            uuidv4(),
      name:          name.trim(),
      email:         email.toLowerCase().trim(),
      password_hash,
      role,
      avatar_id:     null, // User picks avatar from profile page
      is_active:     true,
    });

    const deviceId = req.body.device_id || null;
    const clientIp = req.ip;
    const { accessToken, refreshToken, expiresAt } =
      await issueTokenPair(user, deviceId, clientIp);

    logger.info(`New ${role} registered: ${user.id} (${email})`);

    return res.status(201).json({
      success: true,
      message: 'Account created successfully.',
      data: {
        user:   serializeUser(user),
        tokens: {
          access_token:          accessToken,
          refresh_token:         refreshToken,
          refresh_token_expires: expiresAt.toISOString(),
        },
      },
    });
  } catch (error) {
    if (error.name === 'SequelizeUniqueConstraintError') {
      return res.status(409).json({
        success: false,
        message: 'An account with this email address already exists.',
      });
    }
    logger.error('register error:', error);
    return res.status(500).json({ success: false, message: 'Registration failed.' });
  }
}

async function login(req, res) {
  try {
    const { email, password, device_id, fcm_token } = req.body;

    const user = await User.findOne({
      where: { email: email.toLowerCase().trim() },
    });

    if (!user || !user.is_active) {
      return res.status(401).json({
        success: false,
        message: 'Invalid email or password.',
      });
    }

    const passwordMatch = await bcrypt.compare(password, user.password_hash);
    if (!passwordMatch) {
      return res.status(401).json({
        success: false,
        message: 'Invalid email or password.',
      });
    }

    if (fcm_token && fcm_token !== user.fcm_token) {
      await user.update({ fcm_token });
      logger.info(`FCM token updated for user ${user.id}`);
    }

    const clientIp = req.ip;
    const { accessToken, refreshToken, expiresAt } =
      await issueTokenPair(user, device_id, clientIp);

    logger.info(`User logged in: ${user.id} (${user.role}) from IP ${clientIp}`);

    return res.status(200).json({
      success: true,
      message: 'Login successful.',
      data: {
        // Use serializeUser so avatar_id is always included
        user:   serializeUser(user),
        tokens: {
          access_token:          accessToken,
          refresh_token:         refreshToken,
          refresh_token_expires: expiresAt.toISOString(),
        },
      },
    });
  } catch (error) {
    logger.error('login error:', error);
    return res.status(500).json({ success: false, message: 'Login failed.' });
  }
}

async function refresh(req, res) {
  try {
    const { refresh_token: rawToken, device_id } = req.body;

    if (!rawToken) {
      return res.status(400).json({
        success: false,
        message: 'refresh_token is required.',
      });
    }

    const candidates = await RefreshToken.findAll({
      where: {
        device_id:  device_id || null,
        is_revoked: false,
        expires_at: { [Op.gt]: new Date() },
      },
      include: [
        {
          model: User,
          as: 'user',
          attributes: ['id', 'name', 'email', 'role', 'avatar_id', 'fcm_token', 'is_active'],
          where: { is_active: true },
        },
      ],
      order: [['created_at', 'DESC']],
      limit: 10,
    });

    let matchedToken = null;
    let matchedUser  = null;

    for (const candidate of candidates) {
      const isMatch = await bcrypt.compare(rawToken, candidate.token_hash);
      if (isMatch) {
        matchedToken = candidate;
        matchedUser  = candidate.user;
        break;
      }
    }

    if (!matchedToken || !matchedUser) {
      return res.status(401).json({
        success: false,
        message: 'Invalid or expired refresh token.',
        code:    'REFRESH_TOKEN_INVALID',
      });
    }

    await matchedToken.update({ is_revoked: true, revoked_at: new Date() });

    const clientIp = req.ip;
    const { accessToken, refreshToken: newRefreshToken, expiresAt } =
      await issueTokenPair(matchedUser, device_id, clientIp);

    logger.info(`Refresh token rotated for user ${matchedUser.id}`);

    return res.status(200).json({
      success: true,
      message: 'Tokens refreshed successfully.',
      data: {
        tokens: {
          access_token:          accessToken,
          refresh_token:         newRefreshToken,
          refresh_token_expires: expiresAt.toISOString(),
        },
      },
    });
  } catch (error) {
    logger.error('refresh error:', error);
    return res.status(500).json({ success: false, message: 'Token refresh failed.' });
  }
}

async function logout(req, res) {
  try {
    const { refresh_token: rawToken, device_id } = req.body;

    if (!rawToken) {
      return res.status(400).json({
        success: false,
        message: 'refresh_token is required for logout.',
      });
    }

    const candidates = await RefreshToken.findAll({
      where: {
        user_id:    req.user.id,
        is_revoked: false,
        expires_at: { [Op.gt]: new Date() },
      },
      order: [['created_at', 'DESC']],
      limit: 10,
    });

    for (const candidate of candidates) {
      const isMatch = await bcrypt.compare(rawToken, candidate.token_hash);
      if (isMatch) {
        await candidate.update({ is_revoked: true, revoked_at: new Date() });
        logger.info(`User ${req.user.id} logged out from device ${device_id || 'unknown'}`);
        break;
      }
    }

    return res.status(200).json({ success: true, message: 'Logged out successfully.' });
  } catch (error) {
    logger.error('logout error:', error);
    return res.status(500).json({ success: false, message: 'Logout failed.' });
  }
}

async function updateFcmToken(req, res) {
  try {
    const { fcm_token } = req.body;
    if (!fcm_token) {
      return res.status(400).json({ success: false, message: 'fcm_token is required.' });
    }
    await User.update({ fcm_token }, { where: { id: req.user.id } });
    logger.info(`FCM token updated for user ${req.user.id}`);
    return res.status(200).json({ success: true, message: 'FCM token updated successfully.' });
  } catch (error) {
    logger.error('updateFcmToken error:', error);
    return res.status(500).json({ success: false, message: 'FCM token update failed.' });
  }
}

async function getMe(req, res) {
  try {
    const user = await User.findOne({
      where:      { id: req.user.id },
      // Include avatar_id in response
      attributes: ['id', 'name', 'email', 'role', 'avatar_id', 'is_active', 'created_at'],
    });

    if (!user) {
      return res.status(404).json({ success: false, message: 'User not found.' });
    }

    return res.status(200).json({
      success: true,
      data:    { user: serializeUser(user) },
    });
  } catch (error) {
    logger.error('getMe error:', error);
    return res.status(500).json({ success: false, message: 'Failed to fetch profile.' });
  }
}

// ── NEW: updateProfile ────────────────────────────────────────────────────────
/**
 * updateProfile
 * PUT /auth/profile
 * Updates the authenticated user's display name and/or avatar_id.
 *
 * Body: { name?: string, avatar_id?: number (1–5) }
 *
 * Either field is optional — send only what changed.
 * Chat bubbles and the profile page both use avatar_id to pick the preset image.
 */
async function updateProfile(req, res) {
  try {
    const { name, avatar_id } = req.body;

    // At least one field must be provided
    if (name === undefined && avatar_id === undefined) {
      return res.status(400).json({
        success: false,
        message: 'Provide at least one field to update: name or avatar_id.',
      });
    }

    // Build update payload — only include provided fields
    const updates = {};

    if (name !== undefined) {
      const trimmedName = name.trim();
      if (trimmedName.length < 2 || trimmedName.length > 120) {
        return res.status(400).json({
          success: false,
          message: 'Name must be between 2 and 120 characters.',
        });
      }
      updates.name = trimmedName;
    }

    if (avatar_id !== undefined) {
      const avatarNum = parseInt(avatar_id, 10);
      if (isNaN(avatarNum) || avatarNum < 1 || avatarNum > 5) {
        return res.status(400).json({
          success: false,
          message: 'avatar_id must be an integer between 1 and 5.',
        });
      }
      updates.avatar_id = avatarNum;
    }

    // Apply update
    await User.update(updates, { where: { id: req.user.id } });

    // Fetch fresh record to return complete profile
    const updatedUser = await User.findOne({
      where:      { id: req.user.id },
      attributes: ['id', 'name', 'email', 'role', 'avatar_id', 'is_active'],
    });

    logger.info(
      `Profile updated for user ${req.user.id}: ${JSON.stringify(updates)}`
    );

    return res.status(200).json({
      success: true,
      message: 'Profile updated successfully.',
      data:    { user: serializeUser(updatedUser) },
    });
  } catch (error) {
    logger.error('updateProfile error:', error);
    return res.status(500).json({ success: false, message: 'Profile update failed.' });
  }
}

module.exports = {
  register,
  login,
  refresh,
  logout,
  updateFcmToken,
  getMe,
  updateProfile, // NEW
};