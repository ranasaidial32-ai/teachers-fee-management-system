/**
 * app.js
 * EduPay Backend — Main application entry point.
 *
 * Responsibilities:
 *  1. Load environment variables
 *  2. Initialise Firebase Admin SDK (non-fatal in development)
 *  3. Connect to MySQL via Sequelize (with sync in development)
 *  4. Mount Express middleware (security, CORS, logging, body parsing)
 *  5. Mount all REST API route handlers
 *  6. Attach Socket.IO for real-time chat (WebSocket)
 *  7. Start node-cron jobs (fee overdue check + R2 file cleanup)
 *  8. Start HTTP server
 *
 * PRD Reference: Sections 05, 06, 07, 08, 12
 */

'use strict';

// ─── Environment ─────────────────────────────────────────────────────────────
// Must be loaded BEFORE any other module reads process.env
require('dotenv').config();

// ─── Core Node ───────────────────────────────────────────────────────────────
const http = require('http');

// ─── Third-Party ─────────────────────────────────────────────────────────────
const express   = require('express');
const helmet    = require('helmet');
const cors      = require('cors');
const morgan    = require('morgan');
const rateLimit = require('express-rate-limit');

// ─── Internal Config ─────────────────────────────────────────────────────────
const logger             = require('./config/logger');
const { testConnection } = require('./config/database');
const { initFirebase }   = require('./config/firebase');
const { sequelize }      = require('./models/index');

// ─── Route Handlers ──────────────────────────────────────────────────────────
const authRoutes         = require('./routes/auth.routes');
const batchRoutes        = require('./routes/batch.routes');
const feeRoutes          = require('./routes/fee.routes');
const chatRoutes         = require('./routes/chat.routes');
const fileRoutes         = require('./routes/file.routes');
const notificationRoutes = require('./routes/notification.routes');

// ─── Socket.IO Handler ───────────────────────────────────────────────────────
const initSocket = require('./socket/socket');

// ─── Cron Jobs ───────────────────────────────────────────────────────────────
const { startFeeOverdueCron }  = require('./cron/feeOverdue.cron');
const { startFileCleanupCron } = require('./cron/fileCleanup.cron');

// ─────────────────────────────────────────────────────────────────────────────
//  Application Bootstrap
// ─────────────────────────────────────────────────────────────────────────────

async function bootstrap() {

  // 1. Validate DB connection — crash fast if MySQL credentials are wrong
  await testConnection();

  // 2. Sync Sequelize models in development only
  //    Production → use src/database/migrate.js
  if (process.env.NODE_ENV === 'development') {
    await sequelize.sync({ alter: true });
    logger.info('📦  Sequelize models synced (alter: true) — development mode.');
  }

  // 3. Initialise Firebase Admin SDK
  //    FIX: initFirebase() now returns { app, available } — never calls
  //    process.exit() in development. FCM calls become no-ops if unavailable.
  const { available: firebaseAvailable } = initFirebase();

  if (!firebaseAvailable) {
    logger.warn('🔕  FCM push notifications disabled.');
    logger.warn('    Auth / Batches / Fees / Chat work normally.');
    logger.warn('    To enable: add firebase-service-account.json');
  } else {
    logger.info('🔔  FCM push notifications enabled.');
  }

  // ─── Express App ─────────────────────────────────────────────────────────
  const app = express();

  // 4. Security middleware (PRD Section 10)
  app.use(helmet());

  // CORS — allow Flutter app in production; open in development
  app.use(
    cors({
      origin:
        process.env.NODE_ENV === 'production'
          ? process.env.CLIENT_URL
          : '*',
      methods:        ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
      allowedHeaders: ['Content-Type', 'Authorization'],
      credentials:    true,
    })
  );

  // 5. HTTP request logging (skip in test)
  if (process.env.NODE_ENV !== 'test') {
    app.use(
      morgan('combined', {
        stream: { write: (msg) => logger.http(msg.trim()) },
      })
    );
  }

  // 6. Body parsers
  app.use(express.json({ limit: '10mb' }));
  app.use(express.urlencoded({ extended: true, limit: '10mb' }));

  // 7. Global rate limiter — 100 req / 15 min / IP
  const globalLimiter = rateLimit({
    windowMs:       15 * 60 * 1000,
    max:            100,
    standardHeaders: true,
    legacyHeaders:   false,
    message: {
      success: false,
      message: 'Too many requests. Please try again after 15 minutes.',
    },
  });
  app.use(globalLimiter);

  // 8. Health-check endpoint (Railway / Render keep-alive)
  app.get('/health', (_req, res) => {
    res.json({
      status:      'ok',
      service:     'EduPay Backend',
      timestamp:   new Date().toISOString(),
      environment: process.env.NODE_ENV,
      firebase:    firebaseAvailable ? 'enabled' : 'disabled',
    });
  });

  // 9. Mount API routes (PRD Section 09)
  app.use('/api/v1/auth',          authRoutes);
  app.use('/api/v1/batches',       batchRoutes);
  app.use('/api/v1/fees',          feeRoutes);
  app.use('/api/v1/chat',          chatRoutes);
  app.use('/api/v1/files',         fileRoutes);
  app.use('/api/v1/notifications', notificationRoutes);

  // 10. 404 handler
  app.use((_req, res) => {
    res.status(404).json({ success: false, message: 'Route not found.' });
  });

  // 11. Global error handler
  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    logger.error('Unhandled error:', err);
    const status  = err.status || err.statusCode || 500;
    const message = process.env.NODE_ENV === 'production'
      ? 'An internal server error occurred.'
      : err.message;
    res.status(status).json({ success: false, message });
  });

  // ─── HTTP Server & Socket.IO ──────────────────────────────────────────────
  const server = http.createServer(app);

  // 12. Socket.IO for real-time group chat (PRD Section 06)
  initSocket(server);

  // ─── Cron Jobs ────────────────────────────────────────────────────────────
  // 13. Daily fee overdue check — 00:01 UTC (PRD Section 05)
  startFeeOverdueCron();

  // 14. R2 file cleanup — 12h after upload (PRD Section 07)
  startFileCleanupCron();

  // ─── Start Server ─────────────────────────────────────────────────────────
  const PORT = parseInt(process.env.PORT, 10) || 5000;

  const os = require('os');
  function getLocalIP() {
    const nets = os.networkInterfaces();
    for (const name of Object.keys(nets)) {
      for (const net of nets[name]) {
        if (net.family === 'IPv4' && !net.internal) {
          return net.address;
        }
      }
    }
    return 'localhost';
  }

  // ✅ CHANGE THIS — add '0.0.0.0' explicitly
  server.listen(PORT, '0.0.0.0', () => {
    const localIP = getLocalIP();

    logger.info('');
    logger.info('┌─────────────────────────────────────────────┐');
    logger.info('│  🚀  EduPay Backend                         │');
    logger.info(`│  Port:    ${String(PORT).padEnd(34)}│`);
    logger.info(`│  Mode:    ${String(process.env.NODE_ENV).padEnd(34)}│`);
    logger.info(`│  Local:   http://localhost:${PORT}/api/v1${' '.repeat(Math.max(0,17-String(PORT).length))}│`);
    logger.info(`│  Network: http://${localIP}:${PORT}/api/v1${' '.repeat(Math.max(0,14-localIP.length-String(PORT).length))}│`);
    logger.info(`│  Firebase: ${firebaseAvailable ? '✅ enabled ' : '⚠️  disabled'}                        │`);
    logger.info('└─────────────────────────────────────────────┘');
    logger.info('');
    logger.info(`📱  Use this URL in Flutter: http://${localIP}:${PORT}/api/v1`);
  });

  // 15. Graceful shutdown
  const shutdown = async (signal) => {
    logger.info(`${signal} received — shutting down gracefully...`);
    server.close(async () => {
      await sequelize.close();
      logger.info('MySQL connection pool closed. Goodbye.');
      process.exit(0);
    });
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT',  () => shutdown('SIGINT'));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Run
// ─────────────────────────────────────────────────────────────────────────────
bootstrap().catch((err) => {
  console.error('Fatal bootstrap error:', err);
  process.exit(1);
});