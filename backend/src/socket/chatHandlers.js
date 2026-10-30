/**
 * socket/chatHandlers.js
 *
 * NEW LOGIC:
 *  1. On send_message  → create MessageDelivery rows for all enrolled students
 *  2. On message_delivered ACK → mark downloaded_at, check 99% threshold → auto-delete
 *  3. On message_read  → mark read_at, broadcast reader info to batch room
 *  4. Reader list API  → GET /chat/:batchId/messages/:messageId/readers
 */

'use strict';

const { v4: uuidv4 } = require('uuid');
const { Op } = require('sequelize');
const {
  Message,
  MessageDelivery,
  FileRecord,
  Enrollment,
  Batch,
  User,
} = require('../models/index');
const logger = require('../config/logger');

const VALID_MESSAGE_TYPES = new Set(['text', 'image', 'file', 'folder', 'voice']);
const MAX_CONTENT_LENGTH  = 65536;

// Threshold: delete message from DB once this fraction have downloaded it
const AUTO_DELETE_THRESHOLD = 0.99; // 99%

function chatHandlers(io, socket) {
  const user = socket.data.user;

  // ─── send_message ──────────────────────────────────────────────────────────
  socket.on('send_message', async (data, ack) => {
    try {
      const {
        batch_id,
        type = 'text',
        content,
        signal_message_key,
        file_record_id,
        client_message_id,
      } = data || {};

      // ── Validation ────────────────────────────────────────────────────────
      if (!batch_id || typeof batch_id !== 'string')
        return emitError(socket, ack, 'batch_id is required.');
      if (!VALID_MESSAGE_TYPES.has(type))
        return emitError(socket, ack, `Invalid type.`);
      if (!content || typeof content !== 'string')
        return emitError(socket, ack, 'content is required.');
      if (content.length > MAX_CONTENT_LENGTH)
        return emitError(socket, ack, 'content too long.');

      const hasAccess = await verifyBatchAccess(batch_id, user);
      if (!hasAccess)
        return emitError(socket, ack, 'Access denied to this batch chat.');

      if (file_record_id && type !== 'text') {
        const fr = await FileRecord.findOne({
          where: { id: file_record_id, uploader_id: user.id },
          attributes: ['id', 'message_id'],
        });
        if (!fr)         return emitError(socket, ack, 'File record not found.');
        if (fr.message_id) return emitError(socket, ack, 'File already linked.');
      }

      // ── Persist Message ───────────────────────────────────────────────────
      const messageId = uuidv4();

      await Message.create({
        id:                 messageId,
        batch_id,
        sender_id:          user.id,
        type,
        content,
        signal_message_key: signal_message_key || null,
        is_deleted:         false,
      });

      if (file_record_id && type !== 'text') {
        await FileRecord.update(
          { message_id: messageId },
          { where: { id: file_record_id, uploader_id: user.id } }
        );
      }

      // ── Create delivery rows for all enrolled students ─────────────────────
      // Teacher is sender — delivery tracking is for students only
      const enrollments = await Enrollment.findAll({
        where:      { batch_id, is_active: true },
        attributes: ['student_id'],
      });

      // Exclude sender if sender is a student
      const studentIds = enrollments
        .map(e => e.student_id)
        .filter(sid => sid !== user.id);

      const totalStudents = studentIds.length;

      if (totalStudents > 0) {
        const deliveryRows = studentIds.map(sid => ({
          id:            uuidv4(),
          message_id:    messageId,
          batch_id,
          student_id:    sid,
          downloaded_at: null,
          read_at:       null,
        }));
        await MessageDelivery.bulkCreate(deliveryRows, { ignoreDuplicates: true });
      }

      // ── Fetch full message for broadcast ──────────────────────────────────
      const fullMessage = await Message.findOne({
        where: { id: messageId },
        include: [
          {
            model:      User,
            as:         'sender',
            attributes: ['id', 'name', 'role'],
          },
          {
            model:    FileRecord,
            as:       'file',
            required: false,
            attributes: [
              'id', 'original_name', 'mime_type',
              'size_bytes', 'signed_url',
              'signed_url_expires_at', 'is_deleted_from_r2',
            ],
          },
        ],
      });

      // ── Broadcast ─────────────────────────────────────────────────────────
      // Include total_students so Flutter knows denominator for tick logic
      io.to(`batch_${batch_id}`).emit('new_message', {
        message:           fullMessage.toJSON(),
        client_message_id: client_message_id || null,
        total_students:    totalStudents,
        downloaded_count:  0,
        reader_count:      0,
        first_reader:      null,
      });

      if (typeof ack === 'function') ack({ success: true, message_id: messageId });

      logger.debug(`Message ${messageId} (${type}) by ${user.id} in batch ${batch_id}`);

    } catch (error) {
      logger.error(`send_message error for user ${user.id}:`, error);
      emitError(socket, ack, 'Failed to send message.');
    }
  });

  // ─── message_delivered ─────────────────────────────────────────────────────
  // Client emits this when it receives + renders a message (acts as download ACK)
  // { message_id: string, batch_id: string }
  socket.on('message_delivered', async (data) => {
    try {
      const { message_id, batch_id } = data || {};
      if (!message_id || !batch_id) return;

      // Only students have delivery rows
      if (user.role !== 'student') return;

      // Mark this student's row as downloaded
      const [updatedCount] = await MessageDelivery.update(
        { downloaded_at: new Date() },
        {
          where: {
            message_id,
            student_id:    user.id,
            downloaded_at: null, // Only update if not already set
          },
        }
      );

      if (updatedCount === 0) return; // Already marked or no row

      // ── Check auto-delete threshold ────────────────────────────────────────
      const totalRows = await MessageDelivery.count({
        where: { message_id },
      });

      const downloadedRows = await MessageDelivery.count({
        where: {
          message_id,
          downloaded_at: { [Op.ne]: null },
        },
      });

      const downloadedCount = downloadedRows;
      const ratio = totalRows > 0 ? downloadedRows / totalRows : 1;

      // Broadcast updated delivery count to batch room
      io.to(`batch_${batch_id}`).emit('delivery_update', {
        message_id,
        batch_id,
        downloaded_count: downloadedCount,
        total_students:   totalRows,
      });

      // Auto-delete from DB when >= 99% have downloaded
      if (ratio >= AUTO_DELETE_THRESHOLD) {
        await _autoDeleteMessage(io, message_id, batch_id);
      }

    } catch (err) {
      logger.error(`message_delivered error for user ${user.id}:`, err);
    }
  });

  // ─── message_read ──────────────────────────────────────────────────────────
  // Client emits when message scrolls into view / chat is opened
  // { message_id: string, batch_id: string }
  socket.on('message_read', async (data) => {
    try {
      const { message_id, batch_id } = data || {};
      if (!message_id || !batch_id) return;

      if (user.role !== 'student') return;

      // Mark read (only once)
      const [updatedCount] = await MessageDelivery.update(
        { read_at: new Date() },
        {
          where: {
            message_id,
            student_id: user.id,
            read_at:    null,
          },
        }
      );

      if (updatedCount === 0) return;

      // Also mark as downloaded if not already
      await MessageDelivery.update(
        { downloaded_at: new Date() },
        {
          where: {
            message_id,
            student_id:    user.id,
            downloaded_at: null,
          },
        }
      );

      // Fetch updated reader info for broadcast
      const readerCount = await MessageDelivery.count({
        where: {
          message_id,
          read_at: { [Op.ne]: null },
        },
      });

      // Get first reader (earliest read_at)
      const firstReaderDelivery = await MessageDelivery.findOne({
        where: {
          message_id,
          read_at: { [Op.ne]: null },
        },
        order: [['read_at', 'ASC']],
        include: [
          {
            model:      User,
            as:         'student',
            attributes: ['id', 'name'],
          },
        ],
      });

      const firstReader = firstReaderDelivery
        ? {
            id:   firstReaderDelivery.student.id,
            name: firstReaderDelivery.student.name,
          }
        : null;

      // Broadcast read update to entire batch room
      // Teacher UI updates the reader avatar row in real time
      io.to(`batch_${batch_id}`).emit('read_update', {
        message_id,
        batch_id,
        reader_count: readerCount,
        first_reader: firstReader,
        read_by: {
          id:   user.id,
          name: user.name,
        },
      });

    } catch (err) {
      logger.error(`message_read error for user ${user.id}:`, err);
    }
  });

  // ─── signal_key_bundle ─────────────────────────────────────────────────────
  socket.on('signal_key_bundle', async (data, ack) => {
    try {
      const { batch_id, identity_key, signed_pre_key, one_time_pre_keys } = data || {};
      if (!batch_id || !identity_key)
        return emitError(socket, ack, 'batch_id and identity_key required.');

      const hasAccess = await verifyBatchAccess(batch_id, user);
      if (!hasAccess) return emitError(socket, ack, 'Access denied.');

      socket.to(`batch_${batch_id}`).emit('key_bundle_received', {
        user_id:           user.id,
        user_name:         user.name,
        batch_id,
        identity_key,
        signed_pre_key,
        one_time_pre_keys: one_time_pre_keys || [],
        timestamp:         new Date().toISOString(),
      });

      if (typeof ack === 'function')
        ack({ success: true, message: 'Key bundle relayed.' });

    } catch (err) {
      logger.error(`signal_key_bundle error for user ${user.id}:`, err);
      emitError(socket, ack, 'Failed to relay key bundle.');
    }
  });

  // ─── request_key_bundle ────────────────────────────────────────────────────
  socket.on('request_key_bundle', ({ batch_id, target_user_id }) => {
    io.to(`user_${target_user_id}`).emit('key_bundle_requested', {
      batch_id,
      requesting_user_id:   user.id,
      requesting_user_name: user.name,
    });
  });

  // ─── ping ──────────────────────────────────────────────────────────────────
  socket.on('ping', (_, ack) => {
    if (typeof ack === 'function')
      ack({ pong: true, server_time: new Date().toISOString() });
  });
}

// ─── Auto-delete helper ────────────────────────────────────────────────────────

async function _autoDeleteMessage(io, messageId, batchId) {
  try {
    const message = await Message.findOne({
      where: { id: messageId, is_deleted: false },
      attributes: ['id'],
    });

    if (!message) return;

    // Hard delete delivery rows first (cascade would handle it but be explicit)
    await MessageDelivery.destroy({ where: { message_id: messageId } });

    // Soft-delete the message (keeps history reference intact)
    await Message.update(
      {
        is_deleted: true,
        deleted_at: new Date(),
        content:    '[Message auto-removed after delivery]',
      },
      { where: { id: messageId } }
    );

    // Notify room so Flutter removes it from local list
    io.to(`batch_${batchId}`).emit('message_auto_deleted', {
      message_id: messageId,
      batch_id:   batchId,
      reason:     'delivered_to_all',
    });

    logger.info(`Message ${messageId} auto-deleted after 99% delivery in batch ${batchId}`);

  } catch (err) {
    logger.error(`_autoDeleteMessage error for ${messageId}:`, err);
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function verifyBatchAccess(batchId, user) {
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
  } catch { return false; }
}

function emitError(socket, ack, message) {
  const payload = { success: false, message };
  if (typeof ack === 'function') ack(payload);
  else socket.emit('message_error', payload);
}

module.exports = chatHandlers;