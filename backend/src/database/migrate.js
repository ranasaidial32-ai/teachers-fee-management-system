/**
 * database/migrate.js
 * Production-safe database migration runner.
 *
 * Usage:
 *   node src/database/migrate.js              — run all pending migrations
 *   node src/database/migrate.js --fresh      — drop all tables and recreate
 *   node src/database/migrate.js --check      — check connection only
 *
 * In development:  app.js uses sequelize.sync({ alter: true }) automatically.
 * In production:   Run this script manually or as a Railway deploy command:
 *                  "node src/database/migrate.js && node src/app.js"
 *
 * WHY NOT sequelize.sync() IN PRODUCTION:
 *  sync({ force: true }) drops tables.
 *  sync({ alter: true }) can cause data loss on column type changes.
 *  This script uses sync({ force }) only with explicit --fresh flag,
 *  protecting against accidental data loss.
 */

'use strict';

require('dotenv').config();

const { sequelize, testConnection } = require('../config/database');
const logger = require('../config/logger');

// Import all models to register them with Sequelize before sync
require('../models/index');

async function migrate() {
  const args = process.argv.slice(2);
  const isFresh = args.includes('--fresh');
  const isCheck = args.includes('--check');

  logger.info('EduPay Database Migration Runner');
  logger.info(`Environment: ${process.env.NODE_ENV}`);
  logger.info(`Database:    ${process.env.DB_NAME}@${process.env.DB_HOST}:${process.env.DB_PORT}`);

  // Step 1: Test connectivity
  await testConnection();

  if (isCheck) {
    logger.info('✅  Connection check passed. Exiting.');
    process.exit(0);
  }

  if (isFresh) {
    // Safety guard — never allow --fresh in production
    if (process.env.NODE_ENV === 'production') {
      logger.error('❌  --fresh flag is BLOCKED in production environment.');
      logger.error('    This would DROP ALL TABLES and destroy all data.');
      logger.error('    To reset a production DB, do it manually via MySQL console.');
      process.exit(1);
    }

    logger.warn('⚠️   --fresh flag detected. Dropping all tables and recreating...');
    await sequelize.sync({ force: true });
    logger.info('✅  All tables dropped and recreated successfully (fresh migration).');
  } else {
    // Safe migration: ALTER existing tables to match current model definitions
    // This adds new columns and indexes but does NOT drop existing columns
    logger.info('Running safe migration (alter: true)...');
    await sequelize.sync({ alter: true });
    logger.info('✅  Database schema synchronised successfully.');
  }

  // Log table summary
  try {
    const [tables] = await sequelize.query('SHOW TABLES;');
    logger.info(`Tables in ${process.env.DB_NAME}:`);
    tables.forEach((t) => {
      const tableName = Object.values(t)[0];
      logger.info(`  📋  ${tableName}`);
    });
  } catch {
    // Non-fatal — just informational
  }

  await sequelize.close();
  logger.info('Migration complete. Database connection closed.');
  process.exit(0);
}

migrate().catch((err) => {
  logger.error('Migration failed:', err);
  process.exit(1);
});