/**
 * routes/file.routes.js
 * Express router for file upload and management endpoints.
 *
 * PRD Reference: Section 09 — Chat & Files API Endpoints
 *   POST   /files/upload          Upload file to R2, get signed URL
 *   DELETE /files/:fileId         Delete file from R2 (cron triggered)
 *   GET    /files/:fileId/refresh-url  Refresh expired signed URL
 *
 * PRD Reference: Section 11 — Risks & Mitigations
 *   "Enforce max file size (e.g., 25 MB)"
 *   "Compress images before upload"
 *
 * MULTER CONFIGURATION:
 *  - Uses memoryStorage (buffer) so we can stream directly to R2
 *  - Max file size: 25 MB (enforced both here and in model validation)
 *  - File type validation: MIME type whitelist in file.controller.js
 *
 * NOTE: multer-s3 is not used here because Cloudflare R2 requires
 * specific endpoint configuration via AWS SDK v3 S3Client directly.
 * We upload from the buffer in the controller.
 */

'use strict';

const { Router }  = require('express');
const multer      = require('multer');
const { param }   = require('express-validator');

const {
  uploadFile,
  deleteFile,
  refreshSignedUrl,
} = require('../controllers/file.controller');

const { authenticate }                  = require('../middleware/auth.middleware');
const { requireAny, requireTeacher }    = require('../middleware/role.middleware');
const { validate, uuidParamValidation } = require('../middleware/validate.middleware');

const router = Router();

// ─── Multer Configuration ─────────────────────────────────────────────────────

const MAX_FILE_SIZE = parseInt(process.env.MAX_FILE_SIZE_BYTES, 10) || 26214400; // 25 MB

/**
 * multerMemoryStorage
 * Stores uploaded file in memory as a Buffer.
 * The buffer is then streamed to R2 in the controller.
 *
 * PRD Section 11: "Enforce max file size (e.g., 25 MB)"
 */
const upload = multer({
  storage: multer.memoryStorage(),

  limits: {
    fileSize:  MAX_FILE_SIZE,
    files:     1,           // One file per request
    fields:    5,           // Limit non-file fields
  },

  fileFilter: (_req, file, cb) => {
    // Basic MIME type pre-check (detailed validation in controller)
    const allowedPrefixes = ['image/', 'audio/', 'application/'];
    const isAllowed = allowedPrefixes.some((prefix) =>
      file.mimetype.startsWith(prefix)
    );

    if (!isAllowed) {
      return cb(
        new multer.MulterError(
          'LIMIT_UNEXPECTED_FILE',
          `File type "${file.mimetype}" is not supported.`
        ),
        false
      );
    }

    return cb(null, true);
  },
});

/**
 * handleMulterError
 * Catches multer-specific errors (file too large, wrong type)
 * and returns structured JSON instead of the default HTML error.
 */
function handleMulterError(err, req, res, next) {
  if (err instanceof multer.MulterError) {
    if (err.code === 'LIMIT_FILE_SIZE') {
      return res.status(413).json({
        success: false,
        message: `File too large. Maximum allowed size is ${MAX_FILE_SIZE / 1024 / 1024} MB.`,
      });
    }

    if (err.code === 'LIMIT_UNEXPECTED_FILE') {
      return res.status(415).json({
        success: false,
        message: err.field || 'Unsupported file type.',
      });
    }

    return res.status(400).json({
      success: false,
      message: err.message || 'File upload error.',
    });
  }

  return next(err);
}

// ─── Routes ───────────────────────────────────────────────────────────────────

router.use(authenticate);

/**
 * POST /api/v1/files/upload
 * Both teacher and student can upload files (PRD Section 06 permissions matrix)
 * Multer processes multipart/form-data before the controller runs
 */
router.post(
  '/upload',
  requireAny,
  upload.single('file'),
  handleMulterError,
  uploadFile
);

/**
 * GET /api/v1/files/:fileId/refresh-url
 * Both roles — refresh expired signed URL while file still exists on R2
 */
router.get(
  '/:fileId/refresh-url',
  requireAny,
  uuidParamValidation('fileId'),
  validate,
  refreshSignedUrl
);

/**
 * DELETE /api/v1/files/:fileId
 * Teacher only — manual deletion or cron-triggered deletion
 * PRD Section 09: "DEL /files/:fileId — Delete file from R2 (cron triggered)"
 */
router.delete(
  '/:fileId',
  requireTeacher,
  uuidParamValidation('fileId'),
  validate,
  deleteFile
);

module.exports = router;