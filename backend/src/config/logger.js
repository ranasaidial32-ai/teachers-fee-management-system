/**
 * config/logger.js
 * Winston logger configuration for EduPay backend.
 *
 * Log levels used across the codebase:
 *  error   — unhandled exceptions, DB failures, FCM dispatch errors
 *  warn    — deprecated usage, token staleness, soft failures
 *  info    — server startup, cron triggers, successful FCM sends
 *  http    — Morgan HTTP request logs
 *  debug   — Sequelize SQL queries (development only)
 *
 * In production:  only 'info' and above are written to console + file
 * In development: 'debug' and above written to console with colours
 *
 * Log files (production):
 *  logs/error.log   — errors only (rotate daily, keep 14 days)
 *  logs/combined.log — all levels (rotate daily, keep 7 days)
 */

'use strict';

const winston = require('winston');
const path    = require('path');
const fs      = require('fs');

// Ensure logs directory exists
const LOG_DIR = path.resolve(process.cwd(), 'logs');
if (!fs.existsSync(LOG_DIR)) {
  fs.mkdirSync(LOG_DIR, { recursive: true });
}

// ─── Custom log format ────────────────────────────────────────────────────────
const logFormat = winston.format.combine(
  // Add ISO timestamp to every log entry
  winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),

  // Add error stack trace when an Error object is passed
  winston.format.errors({ stack: true }),

  // Splat enables printf-style string interpolation (%s, %d, %o)
  winston.format.splat(),

  // Final output format: [LEVEL] TIMESTAMP — message  {meta}
  winston.format.printf(({ level, message, timestamp, stack, ...meta }) => {
    const metaStr = Object.keys(meta).length
      ? '\n' + JSON.stringify(meta, null, 2)
      : '';
    const stackStr = stack ? '\n' + stack : '';
    return `[${level.toUpperCase().padEnd(5)}] ${timestamp} — ${message}${metaStr}${stackStr}`;
  })
);

// ─── Coloured format for development console ──────────────────────────────────
const devFormat = winston.format.combine(
  winston.format.colorize({ all: true }),
  logFormat
);

// ─── Transports ───────────────────────────────────────────────────────────────
const transports = [];

const isDev  = process.env.NODE_ENV === 'development';
const isProd = process.env.NODE_ENV === 'production';

// Console transport — always active
transports.push(
  new winston.transports.Console({
    level: isDev ? 'debug' : 'info',
    format: isDev ? devFormat : logFormat,
    handleExceptions: true,
  })
);

// File transports — production only
if (isProd) {
  // errors only
  transports.push(
    new winston.transports.File({
      filename: path.join(LOG_DIR, 'error.log'),
      level: 'error',
      format: logFormat,
      maxsize: 10 * 1024 * 1024,  // 10 MB per file
      maxFiles: 14,               // keep 14 rotated files (~14 days)
      handleExceptions: true,
    })
  );

  // all levels
  transports.push(
    new winston.transports.File({
      filename: path.join(LOG_DIR, 'combined.log'),
      level: 'info',
      format: logFormat,
      maxsize: 10 * 1024 * 1024,
      maxFiles: 7,
    })
  );
}

// ─── Logger instance ──────────────────────────────────────────────────────────
const logger = winston.createLogger({
  // In test environment suppress all output
  silent: process.env.NODE_ENV === 'test',
  transports,
  exitOnError: false,
});

module.exports = logger;