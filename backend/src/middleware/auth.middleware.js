/**
 * middleware/auth.middleware.js
 * JWT access token verification middleware.
 *
 * PRD Reference: Section 10 — Security & Compliance
 *   "JWT tokens expire in 15 min"
 *   "Role-based access control (RBAC) on all endpoints"
 *
 * USAGE:
 *   router.get('/protected', authenticate, (req, res) => { ... });
 *
 * ON SUCCESS:
 *   Attaches req.user = { id, email, role, name } to the request object.
 *   Downstream route handlers and role middleware can read req.user.role.
 *
 * ON FAILURE:
 *   Returns 401 JSON response immediately.
 *   Does NOT call next() — request is terminated.
 *
 * TOKEN FORMAT:
 *   Authorization: Bearer <access_token>
 *
 * SECURITY NOTES:
 *   - Access tokens are short-lived (15 min) — limits blast radius if stolen
 *   - We DO NOT store access tokens in DB (stateless JWT)
 *   - Refresh tokens ARE stored (hashed) — see RefreshToken model
 *   - On token decode, we fetch fresh user from DB to catch suspended accounts
 */

'use strict';

const jwt    = require('jsonwebtoken');
const { User } = require('../models/index');
const logger   = require('../config/logger');

/**
 * authenticate
 * Verifies Bearer JWT in Authorization header.
 * Attaches req.user on success.
 *
 * @type {import('express').RequestHandler}
 */
async function authenticate(req, res, next) {
  try {
    // 1. Extract token from Authorization header
    const authHeader = req.headers['authorization'];

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        success: false,
        message: 'Access token missing. Provide Authorization: Bearer <token>',
      });
    }

    const token = authHeader.slice(7); // Remove "Bearer " prefix

    // 2. Verify and decode the JWT
    let decoded;
    try {
      decoded = jwt.verify(token, process.env.JWT_ACCESS_SECRET);
    } catch (jwtError) {
      if (jwtError.name === 'TokenExpiredError') {
        return res.status(401).json({
          success: false,
          message: 'Access token has expired. Please refresh your session.',
          code: 'TOKEN_EXPIRED',
        });
      }

      if (jwtError.name === 'JsonWebTokenError') {
        return res.status(401).json({
          success: false,
          message: 'Invalid access token.',
          code: 'TOKEN_INVALID',
        });
      }

      throw jwtError; // Unexpected JWT error — let global handler catch it
    }

    // 3. Fetch fresh user from DB
    //    This catches cases where the account was suspended AFTER the token was issued
    const user = await User.findOne({
      where: { id: decoded.id, is_active: true },
      attributes: ['id', 'name', 'email', 'role', 'fcm_token'],
    });

    if (!user) {
      return res.status(401).json({
        success: false,
        message: 'User account not found or has been deactivated.',
        code: 'ACCOUNT_INACTIVE',
      });
    }

    // 4. Attach user to request for downstream handlers
    req.user = {
      id:        user.id,
      name:      user.name,
      email:     user.email,
      role:      user.role,
      fcm_token: user.fcm_token,
    };

    return next();
  } catch (error) {
    logger.error('Authentication middleware error:', error);
    return res.status(500).json({
      success: false,
      message: 'Authentication service error.',
    });
  }
}

module.exports = { authenticate };