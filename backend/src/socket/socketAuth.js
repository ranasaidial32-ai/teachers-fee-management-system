    /**
     * socket/socketAuth.js
     * Socket.IO middleware that authenticates WebSocket connections.
     *
     * PRD Reference: Section 10 — Security & Compliance
     *   "JWT tokens expire in 15 min"
     *   "Role-based access control (RBAC) on all endpoints"
     *
     * The Flutter client sends the JWT access token in the Socket.IO
     * handshake auth object:
     *
     *   io('https://api.edupay.dev', {
     *     auth: { token: '<access_token>' }
     *   });
     *
     * On the server, socket.handshake.auth.token contains the JWT.
     *
     * ON SUCCESS:
     *   socket.data.user = { id, name, email, role, fcm_token }
     *   next() is called — connection is accepted
     *
     * ON FAILURE:
     *   next(new Error(...)) is called — connection is rejected
     *   Socket.IO sends an error event to the client and closes the connection
     *
     * TOKEN REFRESH:
     *   If the access token is expired, the client must refresh it via
     *   POST /auth/refresh and reconnect with the new token.
     *   Socket.IO does not handle token refresh — it's the client's responsibility.
     */

    'use strict';

    const jwt    = require('jsonwebtoken');
    const { User } = require('../models/index');
    const logger   = require('../config/logger');

    /**
    * socketAuth
    * Socket.IO use() middleware function.
    *
    * @param {import('socket.io').Socket} socket
    * @param {Function} next
    */
    async function socketAuth(socket, next) {
      try {
        // 1. Extract token from handshake
        const token =
          socket.handshake.auth?.token ||          // Primary: auth object
          socket.handshake.headers?.authorization?.replace('Bearer ', ''); // Fallback

        if (!token) {
          logger.warn(`Socket connection rejected — no token. IP: ${socket.handshake.address}`);
          return next(new Error('Authentication required. Provide token in socket.handshake.auth.token'));
        }

        // 2. Verify JWT
        let decoded;
        try {
          decoded = jwt.verify(token, process.env.JWT_ACCESS_SECRET);
        } catch (jwtError) {
          if (jwtError.name === 'TokenExpiredError') {
            logger.warn(`Socket connection rejected — expired token for socket ${socket.id}`);
            return next(new Error('TOKEN_EXPIRED: Access token has expired. Please refresh and reconnect.'));
          }

          logger.warn(`Socket connection rejected — invalid token. Error: ${jwtError.message}`);
          return next(new Error('TOKEN_INVALID: Invalid access token.'));
        }

        // 3. Fetch user from DB (ensures account is still active)
        const user = await User.findOne({
          where: { id: decoded.id, is_active: true },
          attributes: ['id', 'name', 'email', 'role', 'fcm_token'],
        });

        if (!user) {
          logger.warn(`Socket connection rejected — user ${decoded.id} not found or inactive`);
          return next(new Error('ACCOUNT_INACTIVE: User account not found or deactivated.'));
        }

        // 4. Attach user to socket.data (persists for socket lifetime)
        socket.data.user = {
          id:        user.id,
          name:      user.name,
          email:     user.email,
          role:      user.role,
          fcm_token: user.fcm_token,
        };

        logger.debug(`Socket auth OK: user ${user.id} (${user.role})`);
        return next();

      } catch (error) {
        logger.error('socketAuth unexpected error:', error);
        return next(new Error('Authentication service error.'));
      }
    }

    module.exports = socketAuth;