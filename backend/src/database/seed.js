/**
 * database/seed.js
 * Development seed data for EduPay.
 *
 * Creates:
 *  1 Teacher account
 *  3 Student accounts
 *  2 Batches (one active, one future-dated)
 *  Enrollments linking students to batches
 *  Current-month Fee records for each enrollment
 *
 * Usage:
 *   node src/database/seed.js
 *
 * IMPORTANT: Only run in development. Blocked in production.
 *
 * Seed credentials (for local testing only):
 *  Teacher:   teacher@edupay.dev  /  Teacher@123
 *  Student 1: alice@edupay.dev    /  Student@123
 *  Student 2: bob@edupay.dev      /  Student@123
 *  Student 3: carol@edupay.dev    /  Student@123
 */

'use strict';

require('dotenv').config();

const bcrypt = require('bcrypt');
const { v4: uuidv4 } = require('uuid');

const { testConnection } = require('../config/database');
const {
  sequelize,
  User,
  Batch,
  Enrollment,
  Fee,
} = require('../models/index');

const logger = require('../config/logger');

// ─── Guard ────────────────────────────────────────────────────────────────────
if (process.env.NODE_ENV === 'production') {
  logger.error('❌  Seed script is BLOCKED in production environment.');
  process.exit(1);
}

async function seed() {
  logger.info('🌱  Starting EduPay seed...');

  await testConnection();
  await sequelize.sync({ alter: true });

  const BCRYPT_ROUNDS = parseInt(process.env.BCRYPT_ROUNDS, 10) || 12;

  // ─── 1. Create Users ────────────────────────────────────────────────────────
  const teacherPasswordHash  = await bcrypt.hash('Teacher@123', BCRYPT_ROUNDS);
  const studentPasswordHash  = await bcrypt.hash('Student@123', BCRYPT_ROUNDS);

  const [teacher] = await User.findOrCreate({
    where: { email: 'teacher@edupay.dev' },
    defaults: {
      id: uuidv4(),
      name: 'Rajesh Kumar',
      email: 'teacher@edupay.dev',
      password_hash: teacherPasswordHash,
      role: 'teacher',
    },
  });

  const studentData = [
    { name: 'Alice Sharma',  email: 'alice@edupay.dev' },
    { name: 'Bob Mehta',     email: 'bob@edupay.dev' },
    { name: 'Carol Verma',   email: 'carol@edupay.dev' },
  ];

  const students = await Promise.all(
    studentData.map(({ name, email }) =>
      User.findOrCreate({
        where: { email },
        defaults: {
          id: uuidv4(),
          name,
          email,
          password_hash: studentPasswordHash,
          role: 'student',
        },
      }).then(([user]) => user)
    )
  );

  logger.info(`✅  Users created: 1 teacher, ${students.length} students`);

  // ─── 2. Create Batches ──────────────────────────────────────────────────────
  const today = new Date();
  const startOfMonth = new Date(today.getFullYear(), today.getMonth(), 1);

  const [batchA] = await Batch.findOrCreate({
    where: { name: 'Class 10 Science — Batch A' },
    defaults: {
      id: uuidv4(),
      teacher_id: teacher.id,
      name: 'Class 10 Science — Batch A',
      start_date: startOfMonth.toISOString().split('T')[0],
      fee_amount: 1500,
      duration_years: 1,
      grace_period_days: 9,
    },
  });

  const [batchB] = await Batch.findOrCreate({
    where: { name: 'Class 12 Mathematics — Batch B' },
    defaults: {
      id: uuidv4(),
      teacher_id: teacher.id,
      name: 'Class 12 Mathematics — Batch B',
      start_date: startOfMonth.toISOString().split('T')[0],
      fee_amount: 2000,
      duration_years: 2,
      grace_period_days: 7,
    },
  });

  logger.info('✅  Batches created: Batch A (Science), Batch B (Maths)');

  // ─── 3. Enroll Students ─────────────────────────────────────────────────────
  // Alice + Bob → Batch A
  // Bob + Carol → Batch B (Bob is in both batches)
  const enrollments = [
    { batch_id: batchA.id, student_id: students[0].id }, // Alice → A
    { batch_id: batchA.id, student_id: students[1].id }, // Bob   → A
    { batch_id: batchB.id, student_id: students[1].id }, // Bob   → B
    { batch_id: batchB.id, student_id: students[2].id }, // Carol → B
  ];

  await Promise.all(
    enrollments.map(({ batch_id, student_id }) =>
      Enrollment.findOrCreate({
        where: { batch_id, student_id },
        defaults: { id: uuidv4(), batch_id, student_id },
      })
    )
  );

  logger.info('✅  Enrollments created');

  // ─── 4. Create Fee Records for Current Month ───────────────────────────────
  const billingMonth = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}`;

  const feeRecords = [
    // Batch A fees
    { batch_id: batchA.id, student_id: students[0].id, amount: batchA.fee_amount, status: 'paid' },
    { batch_id: batchA.id, student_id: students[1].id, amount: batchA.fee_amount, status: 'pending' },
    // Batch B fees
    { batch_id: batchB.id, student_id: students[1].id, amount: batchB.fee_amount, status: 'overdue' },
    { batch_id: batchB.id, student_id: students[2].id, amount: batchB.fee_amount, status: 'pending' },
  ];

  await Promise.all(
    feeRecords.map(({ batch_id, student_id, amount, status }) =>
      Fee.findOrCreate({
        where: { batch_id, student_id, billing_month: billingMonth },
        defaults: {
          id: uuidv4(),
          batch_id,
          student_id,
          billing_month: billingMonth,
          amount_due: amount,
          status,
          paid_at: status === 'paid' ? new Date() : null,
        },
      })
    )
  );

  logger.info(`✅  Fee records created for billing month: ${billingMonth}`);
  logger.info('');
  logger.info('─── Seed Summary ───────────────────────────────────────');
  logger.info('  Teacher:   teacher@edupay.dev  /  Teacher@123');
  logger.info('  Student 1: alice@edupay.dev    /  Student@123  (Batch A — PAID)');
  logger.info('  Student 2: bob@edupay.dev      /  Student@123  (Batch A — PENDING, Batch B — OVERDUE)');
  logger.info('  Student 3: carol@edupay.dev    /  Student@123  (Batch B — PENDING)');
  logger.info('────────────────────────────────────────────────────────');

  await sequelize.close();
  logger.info('🌱  Seed complete.');
  process.exit(0);
}

seed().catch((err) => {
  logger.error('Seed failed:', err);
  process.exit(1);
});