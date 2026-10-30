/**
 * controllers/chat.controller.js
 * Adds:
 *  GET /chat/:batchId/messages/:messageId/readers
 *    → Teacher can see exactly who has read a message
 */

'use strict';

const { Op }    = require('sequelize');
const {
  Message,
  MessageDelivery,
  User,
  Batch,
  Enrollment,
  FileRecord,
} = require('../models/index');
const logger = require('../config/logger');

// ── getMessages ───────────────────────────────────────────────────────────────
async function getMessages(req, res) {
  try {
    const { batchId } = req.params;
    const { before, limit = 30 } = req.query;
    const pageLimit = Math.min(parseInt(limit, 10) || 30, 50);

    const batch = await Batch.findOne({
      where: { id: batchId, is_active: true },
      attributes: ['id', 'name', 'teacher_id'],
    });
    if (!batch)
      return res.status(404).json({ success: false, message: 'Batch not found.' });

    if (req.user.role === 'teacher') {
      if (batch.teacher_id !== req.user.id)
        return res.status(403).json({ success: false, message: 'Access denied.' });
    } else {
      const enrollment = await Enrollment.findOne({
        where: { batch_id: batchId, student_id: req.user.id, is_active: true },
      });
      if (!enrollment)
        return res.status(403).json({ success: false, message: 'Not enrolled.' });
    }

    const whereClause = { batch_id: batchId, is_deleted: false };

    if (before) {
      const cursorMsg = await Message.findOne({
        where: { id: before, batch_id: batchId },
        attributes: ['created_at'],
      });
      if (cursorMsg)
        whereClause.created_at = { [Op.lt]: cursorMsg.created_at };
    }

    const messages = await Message.findAll({
      where: whereClause,
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
        {
          // Include delivery stats for each message
          model:    MessageDelivery,
          as:       'deliveries',
          required: false,
          attributes: ['student_id', 'downloaded_at', 'read_at'],
          include: [
            {
              model:      User,
              as:         'student',
              attributes: ['id', 'name'],
            },
          ],
        },
      ],
      order: [['created_at', 'DESC']],
      limit: pageLimit,
    });

    // Enrich each message with delivery summary
    const enriched = messages.map(msg => {
      const json       = msg.toJSON();
      const deliveries = json.deliveries || [];
      const readers    = deliveries
        .filter(d => d.read_at !== null)
        .sort((a, b) => new Date(a.read_at) - new Date(b.read_at));

      const downloaded = deliveries.filter(d => d.downloaded_at !== null);

      json.delivery_summary = {
        total_students:   deliveries.length,
        downloaded_count: downloaded.length,
        reader_count:     readers.length,
        first_reader:     readers.length > 0
          ? { id: readers[0].student.id, name: readers[0].student.name }
          : null,
      };

      // Remove raw deliveries array from response (summary is enough)
      delete json.deliveries;
      return json;
    });

    const chronological = [...enriched].reverse();
    const hasMore       = messages.length === pageLimit;
    const nextCursor    = hasMore ? messages[messages.length - 1].id : null;

    return res.status(200).json({
      success: true,
      data: {
        messages: chronological,
        pagination: {
          has_more:    hasMore,
          next_cursor: nextCursor,
          count:       chronological.length,
        },
      },
    });
  } catch (error) {
    logger.error('getMessages error:', error);
    return res.status(500).json({ success: false, message: 'Failed to fetch messages.' });
  }
}

// ── getMessageReaders ─────────────────────────────────────────────────────────
// GET /chat/:batchId/messages/:messageId/readers
// Teacher only — full list of who read the message
async function getMessageReaders(req, res) {
  try {
    const { batchId, messageId } = req.params;

    // Only teacher can view reader list
    if (req.user.role !== 'teacher') {
      return res.status(403).json({ success: false, message: 'Teachers only.' });
    }

    const batch = await Batch.findOne({
      where: { id: batchId, teacher_id: req.user.id },
      attributes: ['id'],
    });
    if (!batch)
      return res.status(404).json({ success: false, message: 'Batch not found.' });

    const deliveries = await MessageDelivery.findAll({
      where: {
        message_id: messageId,
        read_at: { [Op.ne]: null },
      },
      order: [['read_at', 'ASC']],
      include: [
        {
          model:      User,
          as:         'student',
          attributes: ['id', 'name', 'email'],
        },
      ],
    });

    const readers = deliveries.map(d => ({
      student_id:   d.student.id,
      student_name: d.student.name,
      student_email: d.student.email,
      read_at:      d.read_at,
    }));

    return res.status(200).json({
      success: true,
      data: {
        message_id:   messageId,
        reader_count: readers.length,
        readers,
      },
    });
  } catch (error) {
    logger.error('getMessageReaders error:', error);
    return res.status(500).json({ success: false, message: 'Failed to fetch readers.' });
  }
}

// ── deleteMessage ─────────────────────────────────────────────────────────────
async function deleteMessage(req, res) {
  try {
    const { batchId, messageId } = req.params;

    const batch = await Batch.findOne({
      where: { id: batchId, teacher_id: req.user.id },
    });
    if (!batch)
      return res.status(404).json({ success: false, message: 'Batch not found or not owned.' });

    const message = await Message.findOne({
      where: { id: messageId, batch_id: batchId, is_deleted: false },
    });
    if (!message)
      return res.status(404).json({ success: false, message: 'Message not found.' });

    await message.update({
      is_deleted: true,
      deleted_at: new Date(),
      deleted_by: req.user.id,
      content:    '[Message deleted by admin]',
    });

    // Clean delivery rows on manual delete
    await MessageDelivery.destroy({ where: { message_id: messageId } });

    try {
      const io = req.app.get('io');
      if (io) {
        io.to(`batch_${batchId}`).emit('message_deleted', {
          message_id: messageId,
          batch_id:   batchId,
          deleted_by: req.user.id,
        });
      }
    } catch (socketErr) {
      logger.warn('Socket emit failed on delete (non-fatal):', socketErr.message);
    }

    logger.info(`Message ${messageId} deleted by teacher ${req.user.id}`);
    return res.status(200).json({ success: true, message: 'Message deleted.' });

  } catch (error) {
    logger.error('deleteMessage error:', error);
    return res.status(500).json({ success: false, message: 'Failed to delete message.' });
  }
}

module.exports = { getMessages, deleteMessage, getMessageReaders };