/**
 * models/Enrollment.js
 * Junction table linking students ↔ batches.
 *
 * PRD Reference: Section 03 — Student Enrollment
 *   "Assign students to batches; auto-add to the corresponding
 *    batch chat group upon enrollment."
 *
 * FIELDS
 *  id              UUID primary key
 *  batch_id        FK → batches.id
 *  student_id      FK → users.id (must have role='student')
 *  enrolled_at     When the student was added to the batch
 *  is_active       Teacher can remove student without full DELETE
 *                  (preserves fee history)
 */

'use strict';

const { DataTypes } = require('sequelize');

module.exports = function EnrollmentModel(sequelize) {
  const Enrollment = sequelize.define(
    'Enrollment',
    {
      id: {
        type: DataTypes.UUID,
        defaultValue: DataTypes.UUIDV4,
        primaryKey: true,
        allowNull: false,
      },

      batch_id: {
        type: DataTypes.UUID,
        allowNull: false,
        references: { model: 'batches', key: 'id' },
        onDelete: 'CASCADE',
      },

      student_id: {
        type: DataTypes.UUID,
        allowNull: false,
        references: { model: 'users', key: 'id' },
        onDelete: 'CASCADE',
      },

      enrolled_at: {
        type: DataTypes.DATE,
        allowNull: false,
        defaultValue: DataTypes.NOW,
      },

      is_active: {
        type: DataTypes.BOOLEAN,
        allowNull: false,
        defaultValue: true,
        comment: 'False = removed student; preserves fee history records',
      },
    },
    {
      tableName: 'enrollments',
      timestamps: true,
      underscored: true,

      indexes: [
        // Prevent duplicate enrollment of same student in same batch
        {
          unique: true,
          fields: ['batch_id', 'student_id'],
          name: 'idx_enrollments_unique_pair',
        },

        // Look up all batches for a student
        { fields: ['student_id'], name: 'idx_enrollments_student_id' },

        // Look up all students in a batch
        { fields: ['batch_id'], name: 'idx_enrollments_batch_id' },
      ],
    }
  );

  return Enrollment;
};