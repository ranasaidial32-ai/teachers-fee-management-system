/**
 * controllers/batch.controller.js
 * Handles batch creation, retrieval, and student enrollment.
 *
 * PRD Reference: Section 04 — Batch & Fee Management
 * PRD Reference: Section 09 — Batch API Endpoints
 *   POST /batches            Create new batch (teacher only)
 *   GET  /batches            List teacher's batches
 *   GET  /batches/:id        Get batch details & members
 *   PUT  /batches/:id        Update batch details
 *   POST /batches/:id/enroll Enroll student in batch
 *   DELETE /batches/:id/enroll/:studentId  Remove student
 *
 * BUSINESS RULES:
 *  - Only teachers can create/modify batches
 *  - On enrollment, a fee record for the current billing month is
 *    auto-created (status: 'pending')
 *  - On enrollment, the student is auto-added to batch chat (via Socket.IO)
 *  - Removing a student sets enrollment.is_active = false (soft remove)
 *    to preserve fee history
 */

/**
 * controllers/batch.controller.js
 */

'use strict';

const { v4: uuidv4 } = require('uuid');
const { Op }         = require('sequelize');

const {
  Batch,
  User,
  Enrollment,
  Fee,
  sequelize,
} = require('../models/index');

const logger = require('../config/logger');

// ─── Helpers ──────────────────────────────────────────────────────────────────

function getCurrentBillingMonth() {
  const now   = new Date();
  const year  = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  return `${year}-${month}`;
}

async function createFeeRecordForStudent(batchId, studentId, feeAmount, billingMonth) {
  const [fee, created] = await Fee.findOrCreate({
    where: {
      batch_id:      batchId,
      student_id:    studentId,
      billing_month: billingMonth,
    },
    defaults: {
      id:            uuidv4(),
      batch_id:      batchId,
      student_id:    studentId,
      billing_month: billingMonth,
      amount_due:    feeAmount,
      status:        'pending',
    },
  });
  return { fee, created };
}

// ─── createBatch ──────────────────────────────────────────────────────────────

async function createBatch(req, res) {
  try {
    console.log('═══ CREATE BATCH HIT ═══');
    console.log('USER:', req.user?.id, '|', req.user?.role);
    console.log('BODY:', JSON.stringify(req.body, null, 2));

    const {
      name,
      start_date,
      fee_amount,
      duration_years,
      grace_period_days,
    } = req.body;

    const batchId = uuidv4();

    // Create the batch
    await Batch.create({
      id:                batchId,
      teacher_id:        req.user.id,
      name:              String(name).trim(),
      start_date:        String(start_date),
      fee_amount:        parseInt(fee_amount, 10),
      duration_years:    parseInt(duration_years, 10),
      grace_period_days: parseInt(grace_period_days, 10),
      is_active:         true,
    });

    // ✅ CRITICAL FIX: Always re-fetch after create
    // Sequelize .create() can return incomplete object with null timestamps
    // Re-fetching guarantees all DB-generated fields are populated
    const batch = await Batch.findOne({
      where: { id: batchId },
      raw:   false, // Return Sequelize instance with toJSON()
    });

    if (!batch) {
      logger.error(`Batch ${batchId} not found after creation`);
      return res.status(500).json({
        success: false,
        message: 'Batch created but could not be retrieved.',
      });
    }

    // Convert to plain JSON — ensures all fields are serialized
    const batchJson = batch.toJSON();

    console.log('BATCH CREATED JSON:', JSON.stringify(batchJson, null, 2));

    logger.info(`Batch created: ${batchId} ("${name}") by teacher ${req.user.id}`);

    return res.status(201).json({
      success: true,
      message: 'Batch created successfully.',
      data:    { batch: batchJson },
    });
  } catch (error) {
    console.log('CREATE BATCH ERROR:', error.message);
    console.log('STACK:', error.stack);
    logger.error('createBatch error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to create batch.',
      error:   process.env.NODE_ENV === 'development' ? error.message : undefined,
    });
  }
}

// ─── listBatches ─────────────────────────────────────────────────────────────

async function listBatches(req, res) {
  try {
    let batches;

    if (req.user.role === 'teacher') {
      batches = await Batch.findAll({
        where: {
          teacher_id: req.user.id,
          is_active:  true,
        },
        include: [
          {
            model:    Enrollment,
            as:       'enrollments',
            where:    { is_active: true },
            required: false,
            attributes: ['id'],
          },
        ],
        order: [['created_at', 'DESC']],
      });

      const result = batches.map((b) => {
        const json = b.toJSON();
        return {
          ...json,
          student_count: json.enrollments ? json.enrollments.length : 0,
        };
      });

      return res.status(200).json({
        success: true,
        data:    { batches: result },
      });
    }

    // Student: fetch via enrollments
    const enrollments = await Enrollment.findAll({
      where: {
        student_id: req.user.id,
        is_active:  true,
      },
      include: [
        {
          model: Batch,
          as:    'batch',
          where: { is_active: true },
          include: [
            {
              model:      User,
              as:         'teacher',
              attributes: ['id', 'name', 'email'],
            },
          ],
        },
      ],
      order: [['enrolled_at', 'DESC']],
    });

    batches = enrollments.map((e) => e.batch?.toJSON()).filter(Boolean);

    return res.status(200).json({
      success: true,
      data:    { batches },
    });
  } catch (error) {
    logger.error('listBatches error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to fetch batches.',
    });
  }
}

// ─── getBatchById ─────────────────────────────────────────────────────────────

async function getBatchById(req, res) {
  try {
    const { id } = req.params;

    const batch = await Batch.findOne({
      where: { id, is_active: true },
      include: [
        {
          model:      User,
          as:         'teacher',
          attributes: ['id', 'name', 'email'],
        },
        {
          model: User,
          as:    'students',
          through: {
            model:      Enrollment,
            where:      { is_active: true },
            attributes: ['enrolled_at'],
          },
          attributes: ['id', 'name', 'email'],
        },
      ],
    });

    if (!batch) {
      return res.status(404).json({
        success: false,
        message: 'Batch not found.',
      });
    }

    if (req.user.role === 'student') {
      const isEnrolled = batch.students.some((s) => s.id === req.user.id);
      if (!isEnrolled) {
        return res.status(403).json({
          success: false,
          message: 'You are not enrolled in this batch.',
        });
      }
    }

    if (req.user.role === 'teacher' && batch.teacher_id !== req.user.id) {
      return res.status(403).json({
        success: false,
        message: 'You do not have access to this batch.',
      });
    }

    return res.status(200).json({
      success: true,
      data:    { batch: batch.toJSON() },
    });
  } catch (error) {
    logger.error('getBatchById error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to fetch batch.',
    });
  }
}

// ─── updateBatch ──────────────────────────────────────────────────────────────

async function updateBatch(req, res) {
  try {
    const { id } = req.params;
    const { name, fee_amount, duration_years, grace_period_days } = req.body;

    const batch = await Batch.findOne({
      where: { id, teacher_id: req.user.id, is_active: true },
    });

    if (!batch) {
      return res.status(404).json({
        success: false,
        message: 'Batch not found or you do not own it.',
      });
    }

    const updates = {};
    if (name              !== undefined) updates.name              = String(name).trim();
    if (fee_amount        !== undefined) updates.fee_amount        = parseInt(fee_amount, 10);
    if (duration_years    !== undefined) updates.duration_years    = parseInt(duration_years, 10);
    if (grace_period_days !== undefined) updates.grace_period_days = parseInt(grace_period_days, 10);

    await batch.update(updates);

    // Re-fetch for complete data
    const updated = await Batch.findOne({ where: { id } });

    logger.info(`Batch ${id} updated by teacher ${req.user.id}`);

    return res.status(200).json({
      success: true,
      message: 'Batch updated successfully.',
      data:    { batch: updated?.toJSON() ?? batch.toJSON() },
    });
  } catch (error) {
    logger.error('updateBatch error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to update batch.',
    });
  }
}

// ─── enrollStudent ────────────────────────────────────────────────────────────

async function enrollStudent(req, res) {
  const t = await sequelize.transaction();

  try {
    const { id: batchId } = req.params;
    const { student_id }  = req.body;

    const batch = await Batch.findOne({
      where:       { id: batchId, teacher_id: req.user.id, is_active: true },
      transaction: t,
    });

    if (!batch) {
      await t.rollback();
      return res.status(404).json({
        success: false,
        message: 'Batch not found or you do not own it.',
      });
    }

    const student = await User.findOne({
      where:       { id: student_id, role: 'student', is_active: true },
      attributes:  ['id', 'name', 'email', 'fcm_token'],
      transaction: t,
    });

    if (!student) {
      await t.rollback();
      return res.status(404).json({
        success: false,
        message: 'Student not found.',
      });
    }

    const [enrollment, created] = await Enrollment.findOrCreate({
      where:    { batch_id: batchId, student_id },
      defaults: {
        id:        uuidv4(),
        batch_id:  batchId,
        student_id,
        is_active: true,
      },
      transaction: t,
    });

    if (!created && !enrollment.is_active) {
      await enrollment.update({ is_active: true }, { transaction: t });
    }

    if (!created && enrollment.is_active) {
      await t.rollback();
      return res.status(409).json({
        success: false,
        message: 'Student is already enrolled in this batch.',
      });
    }

    const billingMonth = getCurrentBillingMonth();
    const { fee } = await createFeeRecordForStudent(
      batchId,
      student_id,
      batch.fee_amount,
      billingMonth,
    );

    await t.commit();

    logger.info(`Student ${student_id} enrolled in batch ${batchId}`);

    try {
      const io = req.app.get('io');
      if (io) {
        io.to(`batch_${batchId}`).emit('member_joined', {
          batch_id:   batchId,
          student_id: student.id,
          name:       student.name,
        });
        io.to(`user_${student.id}`).emit('enrolled_in_batch', {
          batch_id:   batchId,
          batch_name: batch.name,
        });
      }
    } catch (socketError) {
      logger.warn('Socket emit failed (non-fatal):', socketError.message);
    }

    return res.status(201).json({
      success: true,
      message: `${student.name} enrolled in ${batch.name}.`,
      data:    { enrollment: enrollment.toJSON(), fee: fee.toJSON() },
    });
  } catch (error) {
    await t.rollback();
    logger.error('enrollStudent error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to enroll student.',
    });
  }
}

// ─── removeStudent ────────────────────────────────────────────────────────────

async function removeStudent(req, res) {
  try {
    const { id: batchId, studentId } = req.params;

    const batch = await Batch.findOne({
      where: { id: batchId, teacher_id: req.user.id },
    });

    if (!batch) {
      return res.status(404).json({
        success: false,
        message: 'Batch not found or you do not own it.',
      });
    }

    const enrollment = await Enrollment.findOne({
      where: { batch_id: batchId, student_id: studentId, is_active: true },
    });

    if (!enrollment) {
      return res.status(404).json({
        success: false,
        message: 'Active enrollment not found.',
      });
    }

    await enrollment.update({ is_active: false });

    try {
      const io = req.app.get('io');
      if (io) {
        io.to(`batch_${batchId}`).emit('member_removed', {
          batch_id:   batchId,
          student_id: studentId,
        });
        io.to(`user_${studentId}`).emit('removed_from_batch', {
          batch_id:   batchId,
          batch_name: batch.name,
        });
      }
    } catch (socketError) {
      logger.warn('Socket emit failed (non-fatal):', socketError.message);
    }

    logger.info(`Student ${studentId} removed from batch ${batchId}`);

    return res.status(200).json({
      success: true,
      message: 'Student removed from batch.',
    });
  } catch (error) {
    logger.error('removeStudent error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to remove student.',
    });
  }
}

// ─── searchStudents ───────────────────────────────────────────────────────────
// GET /batches/:id/search-students?name=xxx
// Returns ALL non-enrolled students when name is empty,
// or filtered results when name is provided.

async function searchStudents(req, res) {
  try {
    const { id: batchId } = req.params;
    const { name }        = req.query;
    const searchName      = name ? String(name).trim() : '';

    // Verify teacher owns this batch
    const batch = await Batch.findOne({
      where: { id: batchId, teacher_id: req.user.id, is_active: true },
    });

    if (!batch) {
      return res.status(404).json({
        success: false,
        message: 'Batch not found or you do not own it.',
      });
    }

    // Find already-enrolled student IDs to exclude them
    const enrolled    = await Enrollment.findAll({
      where:      { batch_id: batchId, is_active: true },
      attributes: ['student_id'],
    });
    const enrolledIds = enrolled.map((e) => e.student_id);

    // Build where clause — if name provided, filter; otherwise return all
    const whereClause = {
      role:      'student',
      is_active: true,
      // Exclude already-enrolled students
      ...(enrolledIds.length > 0 && {
        id: { [Op.notIn]: enrolledIds },
      }),
      // Only add name filter if search term is long enough
      ...(searchName.length >= 2 && {
        name: { [Op.like]: `%${searchName}%` },
      }),
    };

    const students = await User.findAll({
      where:      whereClause,
      attributes: ['id', 'name', 'email'],
      limit:      50,   // Return up to 50 students in the list
      order:      [['name', 'ASC']],
    });

    return res.status(200).json({
      success: true,
      data:    { students: students.map((s) => s.toJSON()) },
    });
  } catch (error) {
    logger.error('searchStudents error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to search students.',
    });
  }
}

module.exports = {
  createBatch,
  listBatches,
  getBatchById,
  updateBatch,
  enrollStudent,
  removeStudent,
  searchStudents,   // ← ADD THIS
};