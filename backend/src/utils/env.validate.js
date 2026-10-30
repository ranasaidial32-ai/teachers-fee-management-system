/**
 * backend/src/utils/env.validate.js
 * Environment Variable Validation Utility
 *
 * PRD Reference: Section 10 — Security & Compliance
 *   JWT secrets, Firebase, R2 keys must all be present.
 *   "All API calls over HTTPS (TLS 1.3)"
 *   "Passwords hashed with bcrypt (12 rounds)"
 *
 * Called at the top of backend/src/app.js before any other
 * module is initialised, so the server fails fast with a
 * clear error message if any required variable is missing.
 *
 * VARIABLES FROM backend/.env.example:
 *   Server:    NODE_ENV, PORT, CLIENT_URL
 *   Database:  DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASS
 *   JWT:       JWT_ACCESS_SECRET, JWT_REFRESH_SECRET,
 *              JWT_ACCESS_EXPIRES_IN, JWT_REFRESH_EXPIRES_IN
 *   Firebase:  FIREBASE_SERVICE_ACCOUNT_PATH
 *   R2:        R2_ACCOUNT_ID, R2_ACCESS_KEY_ID,
 *              R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME,
 *              R2_PUBLIC_URL, R2_SIGNED_URL_EXPIRES
 *   Cron:      FEE_CRON_SCHEDULE
 *   Files:     FILE_DELETE_AFTER_HOURS, MAX_FILE_SIZE_BYTES
 *   Security:  BCRYPT_ROUNDS
 *
 * USAGE:
 *   // First line of app.js, before any other imports
 *   require('./utils/env.validate');
 */

'use strict';

const fs     = require('fs');
const path   = require('path');

// ─── Validation Rules ─────────────────────────────────────────────────────────

/**
 * Each rule:
 *   key      {string}   — process.env key name
 *   required {boolean}  — hard fail if missing
 *   type     {string}   — 'string'|'number'|'boolean'|'path'|'cron'|'url'
 *   min      {number}   — minimum string length or numeric value
 *   max      {number}   — maximum numeric value
 *   values   {string[]} — allowed values (enum)
 *   secret   {boolean}  — mask value in log output
 *   description {string} — shown in validation error message
 */
const ENV_RULES = [

  // ── Server ──────────────────────────────────────────────────────────────
  {
    key:         'NODE_ENV',
    required:    true,
    type:        'string',
    values:      ['development', 'production', 'test'],
    description: 'Runtime environment (development|production|test)',
  },
  {
    key:         'PORT',
    required:    false,
    type:        'number',
    min:         1024,
    max:         65535,
    description: 'HTTP server port (default: 5000)',
  },
  {
    key:         'CLIENT_URL',
    required:    false,
    type:        'url',
    description: 'Allowed CORS origin for the Flutter app / web client',
  },

  // ── MySQL Database ──────────────────────────────────────────────────────
  {
    key:         'DB_HOST',
    required:    true,
    type:        'string',
    min:         1,
    description: 'MySQL host (e.g. localhost or PlanetScale hostname)',
  },
  {
    key:         'DB_PORT',
    required:    false,
    type:        'number',
    min:         1,
    max:         65535,
    description: 'MySQL port (default: 3306)',
  },
  {
    key:         'DB_NAME',
    required:    true,
    type:        'string',
    min:         1,
    description: 'MySQL database name (e.g. edupay_db)',
  },
  {
    key:         'DB_USER',
    required:    true,
    type:        'string',
    min:         1,
    description: 'MySQL username',
  },
  {
    key:         'DB_PASS',
    required:    true,
    type:        'string',
    min:         1,
    secret:      true,
    description: 'MySQL password',
  },

  // ── JWT Auth (PRD Section 10) ────────────────────────────────────────────
  // "JWT tokens expire in 15 min"
  {
    key:         'JWT_ACCESS_SECRET',
    required:    true,
    type:        'string',
    min:         64, // Enforce strong secret (512-bit minimum)
    secret:      true,
    description: 'JWT access token signing secret (min 64 chars)',
  },
  {
    key:         'JWT_REFRESH_SECRET',
    required:    true,
    type:        'string',
    min:         64,
    secret:      true,
    description: 'JWT refresh token signing secret (min 64 chars)',
  },
  {
    key:         'JWT_ACCESS_EXPIRES_IN',
    required:    false,
    type:        'string',
    description: 'Access token TTL (default: 15m — PRD Section 10)',
  },
  {
    key:         'JWT_REFRESH_EXPIRES_IN',
    required:    false,
    type:        'string',
    description: 'Refresh token TTL (default: 7d)',
  },

  // ── Firebase Admin SDK (PRD Section 05) ─────────────────────────────────
  {
    key:         'FIREBASE_SERVICE_ACCOUNT_PATH',
    required:    true,
    type:        'path',
    description: 'Absolute or relative path to Firebase service account JSON',
  },

  // ── Cloudflare R2 (PRD Section 07) ──────────────────────────────────────
  // "Use Cloudflare R2 (free tier: 10 GB/month)"
  {
    key:         'R2_ACCOUNT_ID',
    required:    true,
    type:        'string',
    min:         1,
    description: 'Cloudflare account ID (from Cloudflare dashboard)',
  },
  {
    key:         'R2_ACCESS_KEY_ID',
    required:    true,
    type:        'string',
    min:         1,
    secret:      true,
    description: 'R2 API token Access Key ID',
  },
  {
    key:         'R2_SECRET_ACCESS_KEY',
    required:    true,
    type:        'string',
    min:         1,
    secret:      true,
    description: 'R2 API token Secret Access Key',
  },
  {
    key:         'R2_BUCKET_NAME',
    required:    true,
    type:        'string',
    min:         1,
    description: 'R2 bucket name (e.g. edupay-files)',
  },
  {
    key:         'R2_PUBLIC_URL',
    required:    true,
    type:        'url',
    description: 'R2 bucket public or custom domain URL',
  },
  {
    key:         'R2_SIGNED_URL_EXPIRES',
    required:    false,
    type:        'number',
    min:         300,   // Minimum 5 minutes
    max:         86400, // Maximum 24 hours
    description: 'Signed URL expiry in seconds (PRD: 43200 = 12h)',
  },

  // ── File Management (PRD Section 07) ────────────────────────────────────
  // "Cron job runs 12h after upload; deletes file from R2"
  {
    key:         'FILE_DELETE_AFTER_HOURS',
    required:    false,
    type:        'number',
    min:         1,
    max:         168, // Max 1 week
    description: 'Hours after upload before R2 file deletion (PRD: 12)',
  },
  // "Enforce max file size (e.g., 25 MB)" — PRD Section 11
  {
    key:         'MAX_FILE_SIZE_BYTES',
    required:    false,
    type:        'number',
    min:         1048576,   // 1 MB minimum
    max:         104857600, // 100 MB maximum
    description: 'Maximum upload size in bytes (PRD: 26214400 = 25MB)',
  },

  // ── Cron Schedule (PRD Section 05) ──────────────────────────────────────
  // "Node.js cron job runs daily at 00:01 UTC"
  {
    key:         'FEE_CRON_SCHEDULE',
    required:    false,
    type:        'cron',
    description: 'node-cron schedule for fee overdue check (PRD: "1 0 * * *")',
  },

  // ── Bcrypt (PRD Section 10) ──────────────────────────────────────────────
  // "Passwords hashed with bcrypt (12 rounds)"
  {
    key:         'BCRYPT_ROUNDS',
    required:    false,
    type:        'number',
    min:         10, // Minimum secure rounds
    max:         20, // Practical maximum (too slow beyond this)
    description: 'bcrypt hash rounds (PRD specifies 12)',
  },
];

// ─── Type Validators ──────────────────────────────────────────────────────────

/**
 * Validate a URL string.
 * Accepts http:// and https:// — warns if http in production.
 */
function validateUrl(value, key) {
  try {
    const url = new URL(value);
    if (
      process.env.NODE_ENV === 'production' &&
      url.protocol === 'http:'
    ) {
      // PRD Section 10: "All API calls over HTTPS (TLS 1.3)"
      return `WARNING: ${key} uses HTTP in production — HTTPS required per PRD Section 10`;
    }
    return null; // Valid
  } catch {
    return `${key} must be a valid URL (received: "${value}")`;
  }
}

/**
 * Validate a cron expression (5-field standard format).
 * node-cron uses 6-field (with seconds) — we accept both.
 */
function validateCron(value, key) {
  const cronRegex5 = /^(\*|[0-9,\-/]+)\s+(\*|[0-9,\-/]+)\s+(\*|[0-9,\-/]+)\s+(\*|[0-9,\-/]+)\s+(\*|[0-9,\-/]+)$/;
  const cronRegex6 = /^(\*|[0-9,\-/]+)\s+(\*|[0-9,\-/]+)\s+(\*|[0-9,\-/]+)\s+(\*|[0-9,\-/]+)\s+(\*|[0-9,\-/]+)\s+(\*|[0-9,\-/]+)$/;

  if (!cronRegex5.test(value) && !cronRegex6.test(value)) {
    return `${key} must be a valid cron expression (e.g., "1 0 * * *")`;
  }
  return null;
}

/**
 * Validate a filesystem path exists.
 */
function validatePath(value, key) {
  const resolved = path.resolve(value);
  if (!fs.existsSync(resolved)) {
    return `${key} path does not exist: "${resolved}"`;
  }
  return null;
}

// ─── Main Validator ───────────────────────────────────────────────────────────

/**
 * validateEnv
 * Validates all environment variables against defined rules.
 * Throws on any REQUIRED variable missing or invalid.
 * Logs warnings for optional issues.
 *
 * Called at server startup before any module initialisation.
 */
function validateEnv() {
  const errors   = [];
  const warnings = [];
  const passed   = [];

  for (const rule of ENV_RULES) {
    const value = process.env[rule.key];
    const masked = rule.secret ? '[REDACTED]' : value;

    // ── Missing check ──────────────────────────────────────────────────────
    if (value === undefined || value === '') {
      if (rule.required) {
        errors.push(
          `MISSING (required): ${rule.key}\n` +
          `  → ${rule.description}`
        );
      } else {
        warnings.push(`MISSING (optional): ${rule.key} — ${rule.description}`);
      }
      continue;
    }

    // ── Type checks ────────────────────────────────────────────────────────
    let typeError = null;

    switch (rule.type) {
      case 'number': {
        const num = Number(value);
        if (isNaN(num)) {
          typeError = `${rule.key} must be a number (received: "${masked}")`;
        } else if (rule.min !== undefined && num < rule.min) {
          typeError = `${rule.key} must be ≥ ${rule.min} (received: ${num})`;
        } else if (rule.max !== undefined && num > rule.max) {
          typeError = `${rule.key} must be ≤ ${rule.max} (received: ${num})`;
        }
        break;
      }

      case 'string': {
        if (rule.min !== undefined && value.length < rule.min) {
          typeError = `${rule.key} must be at least ${rule.min} characters (received: ${value.length} chars)`;
        }
        break;
      }

      case 'boolean': {
        if (!['true', 'false', '1', '0'].includes(value.toLowerCase())) {
          typeError = `${rule.key} must be true/false (received: "${masked}")`;
        }
        break;
      }

      case 'url': {
        typeError = validateUrl(value, rule.key);
        if (typeError && typeError.startsWith('WARNING')) {
          warnings.push(typeError);
          typeError = null;
        }
        break;
      }

      case 'path': {
        typeError = validatePath(value, rule.key);
        break;
      }

      case 'cron': {
        typeError = validateCron(value, rule.key);
        break;
      }
    }

    if (typeError) {
      if (rule.required) {
        errors.push(typeError);
      } else {
        warnings.push(`INVALID (optional): ${typeError}`);
      }
      continue;
    }

    // ── Enum check ─────────────────────────────────────────────────────────
    if (rule.values && !rule.values.includes(value)) {
      const err = `${rule.key} must be one of [${rule.values.join('|')}] (received: "${masked}")`;
      if (rule.required) {
        errors.push(err);
      } else {
        warnings.push(err);
      }
      continue;
    }

    passed.push(`  ✓ ${rule.key}${rule.secret ? ' [REDACTED]' : `: ${value}`}`);
  }

  // ── Production-specific extra checks ──────────────────────────────────────
  if (process.env.NODE_ENV === 'production') {
    // Ensure secrets are not left as placeholder values
    const placeholderPatterns = [
      'your_',
      'yourpassword',
      'PLACEHOLDER',
      'changeme',
      'example',
      'xxxxx',
    ];

    const secretKeys = ENV_RULES
      .filter((r) => r.secret)
      .map((r) => r.key);

    for (const key of secretKeys) {
      const val = process.env[key] || '';
      const isPlaceholder = placeholderPatterns.some((p) =>
        val.toLowerCase().includes(p.toLowerCase())
      );
      if (isPlaceholder) {
        errors.push(
          `SECURITY: ${key} appears to contain a placeholder value in production.\n` +
          `  → Replace with a real secret before deploying.`
        );
      }
    }

    // BCrypt rounds must be at least 12 in production (PRD Section 10)
    const bcryptRounds = Number(process.env.BCRYPT_ROUNDS || 12);
    if (bcryptRounds < 12) {
      errors.push(
        `SECURITY: BCRYPT_ROUNDS=${bcryptRounds} is below PRD minimum of 12.\n` +
        `  → PRD Section 10: "Passwords hashed with bcrypt (12 rounds)"`
      );
    }
  }

  // ── Output Results ─────────────────────────────────────────────────────────

  const separator = '═'.repeat(60);

  console.log(`\n${separator}`);
  console.log('  EduPay — Environment Variable Validation');
  console.log(`  NODE_ENV: ${process.env.NODE_ENV || 'undefined'}`);
  console.log(`${separator}`);

  if (passed.length > 0) {
    console.log(`\n✅ Passed (${passed.length}):`);
    passed.forEach((p) => console.log(p));
  }

  if (warnings.length > 0) {
    console.warn(`\n⚠️  Warnings (${warnings.length}):`);
    warnings.forEach((w) => console.warn(`  ⚠ ${w}`));
  }

  if (errors.length > 0) {
    console.error(`\n❌ Errors (${errors.length}):`);
    errors.forEach((e) => console.error(`\n  ✗ ${e}`));
    console.error(`\n${separator}`);
    console.error('  Server startup aborted — fix all errors above.');
    console.error(`  Reference: backend/.env.example`);
    console.error(`${separator}\n`);
    process.exit(1);
  }

  console.log(`\n${separator}`);
  console.log(`  ✅ All required environment variables validated.`);
  console.log(`${separator}\n`);
}

// ─── Exports ──────────────────────────────────────────────────────────────────

module.exports = { validateEnv };

// Auto-run when required (standard usage)
validateEnv();