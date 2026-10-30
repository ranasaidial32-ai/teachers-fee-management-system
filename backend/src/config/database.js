/**
 * database.js
 * Sequelize connection configuration for MySQL 8.x
 * Uses environment variables exclusively — no hardcoded credentials
 */

'use strict';

const { Sequelize } = require('sequelize');
const logger = require('./logger');

const sequelize = new Sequelize(
  process.env.DB_NAME,
  process.env.DB_USER,
  process.env.DB_PASS,
  {
    host: process.env.DB_HOST,
    port: parseInt(process.env.DB_PORT, 10) || 3306,
    dialect: 'mysql',
    logging: false,

    // Connection pool — prevents exhaustion on free-tier hosting
    pool: {
      max: 10,
      min: 0,
      acquire: 30000,   // max ms to wait for connection before throwing error
      idle: 10000,      // max ms a connection can sit idle before being released
    },

    // Disable Sequelize's default console logging; route through Winston
    logging: (msg) => logger.debug(msg),

    dialectOptions: {
      // Required for MySQL 8.x authentication plugin
      authPlugin: 'mysql_native_password',

      // Keep connection alive on Railway/Render free tier
      connectTimeout: 60000,
    },

    define: {
      // Use snake_case column names in MySQL
      underscored: true,

      // Automatically add created_at / updated_at columns
      timestamps: true,

      // Don't pluralise table names automatically
      freezeTableName: true,
    },
  }
);

/**
 * testConnection
 * Call once at server startup to validate DB credentials.
 * Exits process on failure so the error is immediately visible in logs.
 */
async function testConnection() {
  try {
    await sequelize.authenticate();
    logger.info('✅  MySQL connection established successfully.');
  } catch (error) {
    logger.error('❌  Unable to connect to MySQL database:', error.message);
    process.exit(1);
  }
}

module.exports = { sequelize, testConnection };