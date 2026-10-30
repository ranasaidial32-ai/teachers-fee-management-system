/**
 * models/index.js
 * Central model registry — now includes MessageDelivery.
 */

'use strict';

const { sequelize } = require('../config/database');

const UserModel             = require('./User');
const BatchModel            = require('./Batch');
const EnrollmentModel       = require('./Enrollment');
const FeeModel              = require('./Fee');
const MessageModel          = require('./Message');
const MessageDeliveryModel  = require('./MessageDelivery');
const FileRecordModel       = require('./FileRecord');
const NotificationModel     = require('./Notification');
const RefreshTokenModel     = require('./RefreshToken');

const User            = UserModel(sequelize);
const Batch           = BatchModel(sequelize);
const Enrollment      = EnrollmentModel(sequelize);
const Fee             = FeeModel(sequelize);
const Message         = MessageModel(sequelize);
const MessageDelivery = MessageDeliveryModel(sequelize);
const FileRecord      = FileRecordModel(sequelize);
const Notification    = NotificationModel(sequelize);
const RefreshToken    = RefreshTokenModel(sequelize);

// ─── Associations ─────────────────────────────────────────────────────────────

User.hasMany(Batch, { foreignKey: 'teacher_id', as: 'createdBatches' });
Batch.belongsTo(User, { foreignKey: 'teacher_id', as: 'teacher' });

Batch.belongsToMany(User, {
  through: Enrollment,
  foreignKey: 'batch_id',
  otherKey: 'student_id',
  as: 'students',
});
User.belongsToMany(Batch, {
  through: Enrollment,
  foreignKey: 'student_id',
  otherKey: 'batch_id',
  as: 'enrolledBatches',
});

Enrollment.belongsTo(Batch, { foreignKey: 'batch_id',   as: 'batch'   });
Enrollment.belongsTo(User,  { foreignKey: 'student_id', as: 'student' });
Batch.hasMany(Enrollment,   { foreignKey: 'batch_id',   as: 'enrollments' });
User.hasMany(Enrollment,    { foreignKey: 'student_id', as: 'enrollments' });

Batch.hasMany(Fee, { foreignKey: 'batch_id',   as: 'fees' });
Fee.belongsTo(Batch, { foreignKey: 'batch_id', as: 'batch' });
User.hasMany(Fee,  { foreignKey: 'student_id', as: 'fees' });
Fee.belongsTo(User, { foreignKey: 'student_id', as: 'student' });

Batch.hasMany(Message,   { foreignKey: 'batch_id',  as: 'messages'    });
Message.belongsTo(Batch, { foreignKey: 'batch_id',  as: 'batch'       });
User.hasMany(Message,    { foreignKey: 'sender_id', as: 'sentMessages' });
Message.belongsTo(User,  { foreignKey: 'sender_id', as: 'sender'      });

// MessageDelivery associations
Message.hasMany(MessageDelivery, {
  foreignKey: 'message_id',
  as: 'deliveries',
});
MessageDelivery.belongsTo(Message, {
  foreignKey: 'message_id',
  as: 'message',
});

User.hasMany(MessageDelivery, {
  foreignKey: 'student_id',
  as: 'messageDeliveries',
});
MessageDelivery.belongsTo(User, {
  foreignKey: 'student_id',
  as: 'student',
});

Batch.hasMany(MessageDelivery, {
  foreignKey: 'batch_id',
  as: 'messageDeliveries',
});
MessageDelivery.belongsTo(Batch, {
  foreignKey: 'batch_id',
  as: 'batch',
});

Message.hasOne(FileRecord,    { foreignKey: 'message_id', as: 'file'    });
FileRecord.belongsTo(Message, { foreignKey: 'message_id', as: 'message' });

User.hasMany(Notification,        { foreignKey: 'user_id', as: 'notifications' });
Notification.belongsTo(User,      { foreignKey: 'user_id', as: 'user'          });
User.hasMany(RefreshToken,        { foreignKey: 'user_id', as: 'refreshTokens' });
RefreshToken.belongsTo(User,      { foreignKey: 'user_id', as: 'user'          });

// ─── Exports ──────────────────────────────────────────────────────────────────

module.exports = {
  sequelize,
  User,
  Batch,
  Enrollment,
  Fee,
  Message,
  MessageDelivery,
  FileRecord,
  Notification,
  RefreshToken,
};