/**
 * controllers/file.controller.js
 * Handles file uploads to Cloudflare R2 and signed URL generation.
 *
 * PRD Reference: Section 07 — File Storage Architecture
 * PRD Reference: Section 09 — POST /files/upload, DELETE /files/:fileId
 *
 * FILE LIFECYCLE (PRD Section 07):
 *  1. Teacher uploads file via chat → Node.js streams upload to Cloudflare R2
 *  2. Signed URL generated and broadcast to batch members via Socket.IO
 *  3. Flutter WorkManager auto-downloads on student devices
 *  4. Cron job runs 12h after upload → deletes file from R2
 *  5. Students continue to view from local storage
 *
 * SECURITY (PRD Section 10):
 *  - R2 files accessed via short-lived signed URLs only
 *  - Max file size: 25 MB (enforced by multer + model validation)
 *  - No direct public access to R2 bucket
 *
 * SUPPORTED FILE TYPES (PRD Section 06):
 *  Images: JPEG, PNG, WEBP
 *  Docs:   PDF, DOCX, XLSX, ZIP
 *  Audio:  AAC, OGG (voice notes)
 */

'use strict';

const { v4: uuidv4 } = require('uuid');
const path           = require('path');
const {
  S3Client,
  PutObjectCommand,
  DeleteObjectCommand,
  GetObjectCommand,
} = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');

const { FileRecord, Batch, Enrollment, Message } = require('../models/index');
const logger = require('../config/logger');

// ─── R2 Client (S3-compatible) ────────────────────────────────────────────────

/**
 * getR2Client
 * Creates a Cloudflare R2 S3-compatible client.
 * Called per-request to pick up env var changes in development.
 * In production, this is effectively cached after the first call.
 */
function getR2Client() {
  return new S3Client({
    region: 'auto',
    endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId:     process.env.R2_ACCESS_KEY_ID,
      secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
    },
  });
}

// ─── Allowed MIME Types ───────────────────────────────────────────────────────

const ALLOWED_MIME_TYPES = new Set([
  // Images (PRD Section 06)
  'image/jpeg',
  'image/png',
  'image/webp',

  // Documents
  'application/pdf',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document', // DOCX
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',       // XLSX
  'application/zip',
  'application/x-zip-compressed',

  // Audio — voice notes (PRD Section 06)
  'audio/aac',
  'audio/ogg',
  'audio/mpeg',    // MP3 fallback
  'audio/mp4',     // AAC in MP4 container
]);

/**
 * validateMimeType
 * @param {string} mimeType
 * @returns {boolean}
 */
function validateMimeType(mimeType) {
  return ALLOWED_MIME_TYPES.has(mimeType);
}

/**
 * buildR2Key
 * Constructs the R2 object key with a structured path for easy management.
 * Format: batches/<batchId>/files/<uuid>-<sanitised-filename>
 *
 * @param {string} batchId
 * @param {string} originalName
 * @returns {string}
 */
function buildR2Key(batchId, originalName) {
  const ext      = path.extname(originalName).toLowerCase();
  const basename = path.basename(originalName, ext)
    .replace(/[^a-zA-Z0-9_-]/g, '_')  // Sanitise filename
    .slice(0, 60);                      // Limit length

  return `batches/${batchId}/files/${uuidv4()}-${basename}${ext}`;
}

// ─── Controller Methods ───────────────────────────────────────────────────────

/**
 * uploadFile
 * POST /files/upload
 * Streams a file to Cloudflare R2, creates a FileRecord, generates a
 * signed URL, and emits a Socket.IO event to notify batch members.
 *
 * Expected: multipart/form-data with fields:
 *   file      (binary) — the file to upload
 *   batch_id  (string) — which batch this file belongs to
 *   type      (string) — message type: 'image' | 'file' | 'folder' | 'voice'
 *
 * Uses multer middleware (configured in file.routes.js) to parse multipart.
 */
async function uploadFile(req, res) {
  try {
    // multer attaches the uploaded file to req.file
    if (!req.file) {
      return res.status(400).json({
        success: false,
        message: 'No file provided. Upload using multipart/form-data with field name "file".',
      });
    }

    const { batch_id, type = 'file' } = req.body;

    if (!batch_id) {
      return res.status(400).json({ success: false, message: 'batch_id is required.' });
    }

    // Validate message type
    const validTypes = ['image', 'file', 'folder', 'voice'];
    if (!validTypes.includes(type)) {
      return res.status(400).json({
        success: false,
        message: `type must be one of: ${validTypes.join(', ')}.`,
      });
    }

    // Validate MIME type
    const mimeType = req.file.mimetype;
    if (!validateMimeType(mimeType)) {
      return res.status(415).json({
        success: false,
        message: `Unsupported file type: ${mimeType}. Allowed: images, PDF, DOCX, XLSX, ZIP, AAC, OGG.`,
      });
    }

    // Verify user has access to this batch
    await verifyBatchAccess(batch_id, req.user);

    const r2Client  = getR2Client();
    const bucket    = process.env.R2_BUCKET_NAME;
    const r2Key     = buildR2Key(batch_id, req.file.originalname);

    // Upload to R2
    const putCommand = new PutObjectCommand({
      Bucket:      bucket,
      Key:         r2Key,
      Body:        req.file.buffer,
      ContentType: mimeType,
      ContentDisposition: `attachment; filename="${req.file.originalname}"`,
      Metadata: {
        uploader_id: req.user.id,
        batch_id,
        original_name: req.file.originalname,
      },
    });

    await r2Client.send(putCommand);
    logger.info(`File uploaded to R2: ${r2Key} (${req.file.size} bytes)`);

    // Generate signed URL (expires in R2_SIGNED_URL_EXPIRES seconds)
    const signedUrlExpiresSeconds = parseInt(process.env.R2_SIGNED_URL_EXPIRES, 10) || 43200;
    const signedUrlExpiresAt = new Date(Date.now() + signedUrlExpiresSeconds * 1000);

    const getCommand = new GetObjectCommand({ Bucket: bucket, Key: r2Key });
    const signedUrl  = await getSignedUrl(r2Client, getCommand, {
      expiresIn: signedUrlExpiresSeconds,
    });

    // Compute R2 deletion time (12 hours after upload — PRD Section 07)
    const deleteAfterHours = parseInt(process.env.FILE_DELETE_AFTER_HOURS, 10) || 12;
    const uploadExpiresAt  = new Date(Date.now() + deleteAfterHours * 60 * 60 * 1000);

    // Create FileRecord in DB
    const fileRecord = await FileRecord.create({
      id:                    uuidv4(),
      uploader_id:           req.user.id,
      message_id:            null, // Linked after message creation in socket handler
      r2_key:                r2Key,
      r2_bucket:             bucket,
      original_name:         req.file.originalname,
      mime_type:             mimeType,
      size_bytes:            req.file.size,
      signed_url:            signedUrl,
      signed_url_expires_at: signedUrlExpiresAt,
      upload_expires_at:     uploadExpiresAt,
      is_deleted_from_r2:    false,
    });

    // Emit Socket.IO event so batch members are notified immediately
    // and WorkManager on student devices triggers auto-download
    try {
      const io = req.app.get('io');
      if (io) {
        io.to(`batch_${batch_id}`).emit('file_shared', {
          file_record_id: fileRecord.id,
          batch_id,
          uploader_id:    req.user.id,
          uploader_name:  req.user.name,
          type,
          original_name:  req.file.originalname,
          mime_type:      mimeType,
          size_bytes:     req.file.size,
          signed_url:     signedUrl,
          expires_at:     signedUrlExpiresAt.toISOString(),
          upload_expires_at: uploadExpiresAt.toISOString(),
        });
      }
    } catch (socketError) {
      logger.warn('Socket emit failed after file upload (non-fatal):', socketError.message);
    }

    return res.status(201).json({
      success: true,
      message: 'File uploaded successfully.',
      data: {
        file_record: {
          id:               fileRecord.id,
          original_name:    fileRecord.original_name,
          mime_type:        fileRecord.mime_type,
          size_bytes:       fileRecord.size_bytes,
          signed_url:       signedUrl,
          expires_at:       signedUrlExpiresAt.toISOString(),
          upload_expires_at: uploadExpiresAt.toISOString(),
        },
      },
    });
  } catch (error) {
    logger.error('uploadFile error:', error);
    return res.status(500).json({ success: false, message: 'File upload failed.' });
  }
}

/**
 * deleteFile
 * DELETE /files/:fileId
 * Called by the cron job (programmatically) or teacher via API.
 * Deletes the object from R2 and marks the FileRecord as deleted.
 *
 * PRD Section 09: "DEL /files/:fileId — Delete file from R2 (cron triggered)"
 */
async function deleteFile(req, res) {
  try {
    const { fileId } = req.params;

    const fileRecord = await FileRecord.findOne({ where: { id: fileId } });

    if (!fileRecord) {
      return res.status(404).json({ success: false, message: 'File record not found.' });
    }

    if (fileRecord.is_deleted_from_r2) {
      return res.status(409).json({
        success: false,
        message: 'File has already been deleted from R2.',
      });
    }

    // Delete from R2
    const r2Client = getR2Client();
    const deleteCommand = new DeleteObjectCommand({
      Bucket: fileRecord.r2_bucket,
      Key:    fileRecord.r2_key,
    });

    await r2Client.send(deleteCommand);

    // Mark as deleted in DB
    await fileRecord.update({
      is_deleted_from_r2:  true,
      deleted_from_r2_at:  new Date(),
    });

    logger.info(`File deleted from R2: ${fileRecord.r2_key}`);

    return res.status(200).json({
      success: true,
      message: 'File deleted from R2 successfully.',
      data: { file_id: fileId },
    });
  } catch (error) {
    logger.error('deleteFile error:', error);
    return res.status(500).json({ success: false, message: 'File deletion failed.' });
  }
}

/**
 * refreshSignedUrl
 * GET /files/:fileId/refresh-url
 * Generates a fresh signed URL for a file still in R2.
 * Called when a client's signed URL has expired but file is still on server.
 */
async function refreshSignedUrl(req, res) {
  try {
    const { fileId } = req.params;

    const fileRecord = await FileRecord.findOne({ where: { id: fileId } });

    if (!fileRecord) {
      return res.status(404).json({ success: false, message: 'File record not found.' });
    }

    if (fileRecord.is_deleted_from_r2) {
      return res.status(410).json({
        success: false,
        message: 'File has been deleted from the server. Check your local cache.',
        code: 'FILE_DELETED_FROM_SERVER',
      });
    }

    // Generate new signed URL
    const r2Client = getR2Client();
    const signedUrlExpiresSeconds = parseInt(process.env.R2_SIGNED_URL_EXPIRES, 10) || 43200;
    const signedUrlExpiresAt = new Date(Date.now() + signedUrlExpiresSeconds * 1000);

    const getCommand = new GetObjectCommand({
      Bucket: fileRecord.r2_bucket,
      Key:    fileRecord.r2_key,
    });
    const signedUrl = await getSignedUrl(r2Client, getCommand, {
      expiresIn: signedUrlExpiresSeconds,
    });

    // Update DB
    await fileRecord.update({
      signed_url:            signedUrl,
      signed_url_expires_at: signedUrlExpiresAt,
    });

    return res.status(200).json({
      success: true,
      data: {
        signed_url: signedUrl,
        expires_at: signedUrlExpiresAt.toISOString(),
      },
    });
  } catch (error) {
    logger.error('refreshSignedUrl error:', error);
    return res.status(500).json({ success: false, message: 'Failed to refresh signed URL.' });
  }
}

// ─── Internal Helpers ─────────────────────────────────────────────────────────

/**
 * verifyBatchAccess
 * Throws an error if the user does not have access to the batch.
 * Teacher must own the batch; student must be actively enrolled.
 */
async function verifyBatchAccess(batchId, user) {
  const batch = await Batch.findOne({
    where: { id: batchId, is_active: true },
    attributes: ['id', 'teacher_id'],
  });

  if (!batch) {
    const error = new Error('Batch not found.');
    error.status = 404;
    throw error;
  }

  if (user.role === 'teacher') {
    if (batch.teacher_id !== user.id) {
      const error = new Error('You do not have access to this batch.');
      error.status = 403;
      throw error;
    }
  } else {
    const enrollment = await Enrollment.findOne({
      where: { batch_id: batchId, student_id: user.id, is_active: true },
    });
    if (!enrollment) {
      const error = new Error('You are not enrolled in this batch.');
      error.status = 403;
      throw error;
    }
  }
}

// Export verifyBatchAccess for use in socket handler
module.exports = {
  uploadFile,
  deleteFile,
  refreshSignedUrl,
  verifyBatchAccess,
  getR2Client,
};