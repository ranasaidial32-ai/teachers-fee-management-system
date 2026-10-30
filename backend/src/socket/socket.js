/**
 * socket/socket.js
 * Socket.IO server initialisation and room management.
 *
 * PRD Reference: Section 06 — Encrypted Group Chat
 *   "Chat is powered by WebSocket (Socket.IO) with end-to-end encryption
 *    using the Signal Protocol"
 *
 * PRD Reference: Section 08 — Tech Stack
 *   "Real-time Chat: Socket.IO — WebSocket transport with fallback"
 *
 * ROOM STRATEGY:
 *  Each batch has one Socket.IO room:  batch_<batchId>
 *  Each user has a personal room:      user_<userId>
 *
 *  batch rooms  — broadcast messages, file uploads, member changes
 *  user rooms   — personal notifications (enrollment, removal)
 *
 * CONNECTION LIFECYCLE:
 *  1. Client connects with JWT access token in handshake auth
 *  2. socketAuth middleware verifies JWT
 *  3. Client joins their personal user room automatically
 *  4. Client joins batch rooms for all their active enrollments
 *  5. Chat events handled in chatHandlers.js
 *  6. On disconnect: rooms are left automatically by Socket.IO
 *
 * E2EE NOTE:
 *  The server acts as a relay only. It stores and forwards encrypted
 *  ciphertext. It has no access to the Signal Protocol session keys
 *  held by clients. The server cannot decrypt any message content.
 *
 * SCALING NOTE:
 *  For multi-instance deployments, replace the default in-memory adapter
 *  with socket.io-redis adapter. For MVP/free-tier single instance,
 *  the default adapter is sufficient.
 */

'use strict';

const { Server }    = require('socket.io');
const logger        = require('../config/logger');
const socketAuth    = require('./socketAuth');
const chatHandlers  = require('./chatHandlers');
const { Enrollment, Batch } = require('../models/index');

/**
 * initSocket
 * Attaches Socket.IO to the existing HTTP server.
 * Called once from app.js after the HTTP server is created.
 *
 * @param {import('http').Server} httpServer
 * @returns {import('socket.io').Server}
 */
function initSocket(httpServer) {
  const io = new Server(httpServer, {
    // Transport configuration — WebSocket preferred, polling as fallback
    transports: ['websocket', 'polling'],

    // CORS — allow Flutter client connections
    cors: {
      origin:  process.env.NODE_ENV === 'production'
        ? process.env.CLIENT_URL
        : '*',
      methods: ['GET', 'POST'],
    },

    // Ping settings — keep connections alive on free-tier hosting
    // (Railway/Render idle connections are killed after ~30s)
    pingTimeout:  60000,  // 60s before declaring connection dead
    pingInterval: 25000,  // Send ping every 25s

    // Maximum payload size — 5MB covers encrypted file metadata
    maxHttpBufferSize: 5 * 1024 * 1024,

    // Connection state recovery — buffers events for briefly disconnected clients
    connectionStateRecovery: {
      maxDisconnectionDuration: 2 * 60 * 1000, // 2 minutes
      skipMiddlewares: false,
    },
  });

  // ─── Authentication Middleware ──────────────────────────────────────────────
  // Runs before every connection is accepted
  io.use(socketAuth);

  // ─── Connection Handler ─────────────────────────────────────────────────────
  io.on('connection', async (socket) => {
    const user = socket.data.user;

    logger.info(
      `Socket connected: user ${user.id} (${user.role}) — socket ${socket.id}`
    );

    try {
      // 1. Join personal notification room
      await socket.join(`user_${user.id}`);

      // 2. Join all batch rooms the user belongs to
      const batchRooms = await getBatchRoomsForUser(user);
      for (const room of batchRooms) {
        await socket.join(room);
        logger.debug(`User ${user.id} joined room ${room}`);
      }

      // 3. Acknowledge connection to client with joined rooms
      socket.emit('connected', {
        user_id:      user.id,
        role:         user.role,
        joined_rooms: batchRooms,
        server_time:  new Date().toISOString(),
      });

      // 4. Register chat event handlers
      chatHandlers(io, socket);

      // 5. Handle explicit room join (when enrolled in new batch during session)
      socket.on('join_batch', async ({ batch_id }) => {
        try {
          if (!batch_id || typeof batch_id !== 'string') return;

          // Verify access before joining
          const hasAccess = await verifyBatchRoomAccess(batch_id, user);
          if (!hasAccess) {
            socket.emit('error', { message: 'Access denied to batch room.' });
            return;
          }

          const room = `batch_${batch_id}`;
          await socket.join(room);
          socket.emit('joined_batch', { batch_id, room });
          logger.debug(`User ${user.id} explicitly joined room ${room}`);
        } catch (err) {
          logger.error(`join_batch error for user ${user.id}:`, err);
          socket.emit('error', { message: 'Failed to join batch room.' });
        }
      });

      // 6. Handle explicit room leave
      socket.on('leave_batch', async ({ batch_id }) => {
        const room = `batch_${batch_id}`;
        await socket.leave(room);
        socket.emit('left_batch', { batch_id });
        logger.debug(`User ${user.id} left room ${room}`);
      });

      // 7. Typing indicators
      socket.on('typing_start', ({ batch_id }) => {
        socket.to(`batch_${batch_id}`).emit('user_typing', {
          batch_id,
          user_id:   user.id,
          user_name: user.name,
        });
      });

      socket.on('typing_stop', ({ batch_id }) => {
        socket.to(`batch_${batch_id}`).emit('user_stopped_typing', {
          batch_id,
          user_id: user.id,
        });
      });

      // 8. Online presence — notify batch members
      notifyPresence(io, user, batchRooms, 'online');

      // 9. Disconnect handler
      socket.on('disconnect', (reason) => {
        logger.info(
          `Socket disconnected: user ${user.id} — reason: ${reason}`
        );
        notifyPresence(io, user, batchRooms, 'offline');
      });

      // 10. Error handler for this socket
      socket.on('error', (err) => {
        logger.error(`Socket error for user ${user.id}:`, err);
      });

    } catch (initError) {
      logger.error(`Socket init error for user ${user.id}:`, initError);
      socket.emit('error', { message: 'Server error during connection setup.' });
      socket.disconnect(true);
    }
  });

  // ─── Attach io instance to app for use in controllers ──────────────────────
  // app.js calls: server.listen() after initSocket(), so we need to
  // make io accessible via app.get('io') in controllers
  // The httpServer._app reference is set in app.js via: app.set('io', io)
  // We return io here and app.js assigns it
  logger.info('✅  Socket.IO initialised.');

  return io;
}

// ─── Helper Functions ─────────────────────────────────────────────────────────

/**
 * getBatchRoomsForUser
 * Returns an array of Socket.IO room names the user should join on connect.
 *
 * Teacher: rooms for all active batches they created
 * Student: rooms for all active batches they are enrolled in
 *
 * @param {{ id: string, role: string }} user
 * @returns {Promise<string[]>}
 */
async function getBatchRoomsForUser(user) {
  try {
    if (user.role === 'teacher') {
      const batches = await Batch.findAll({
        where: { teacher_id: user.id, is_active: true },
        attributes: ['id'],
      });
      return batches.map((b) => `batch_${b.id}`);
    }

    // Student
    const enrollments = await Enrollment.findAll({
      where: { student_id: user.id, is_active: true },
      include: [
        {
          model: Batch,
          as: 'batch',
          where: { is_active: true },
          attributes: ['id'],
        },
      ],
      attributes: ['batch_id'],
    });

    return enrollments.map((e) => `batch_${e.batch_id}`);
  } catch (err) {
    logger.error('getBatchRoomsForUser error:', err);
    return [];
  }
}

/**
 * verifyBatchRoomAccess
 * Checks if a user is allowed to join a specific batch room.
 *
 * @param {string} batchId
 * @param {{ id: string, role: string }} user
 * @returns {Promise<boolean>}
 */
async function verifyBatchRoomAccess(batchId, user) {
  try {
    if (user.role === 'teacher') {
      const batch = await Batch.findOne({
        where: { id: batchId, teacher_id: user.id, is_active: true },
        attributes: ['id'],
      });
      return !!batch;
    }

    const enrollment = await Enrollment.findOne({
      where: { batch_id: batchId, student_id: user.id, is_active: true },
      attributes: ['id'],
    });
    return !!enrollment;
  } catch {
    return false;
  }
}

/**
 * notifyPresence
 * Emits an online/offline presence event to all batch rooms the user is in.
 *
 * @param {import('socket.io').Server} io
 * @param {{ id: string, name: string }} user
 * @param {string[]} rooms
 * @param {'online'|'offline'} status
 */
function notifyPresence(io, user, rooms, status) {
  const event = status === 'online' ? 'user_online' : 'user_offline';
  rooms.forEach((room) => {
    io.to(room).emit(event, {
      user_id:   user.id,
      user_name: user.name,
      timestamp: new Date().toISOString(),
    });
  });
}

module.exports = initSocket;