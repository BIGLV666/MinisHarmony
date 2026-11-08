/**
 * Encrypted whole-library backup envelope.
 *
 * The plain backup JSON is encrypted with AES-256-GCM; the key is derived
 * from the user's password with PBKDF2-HMAC-SHA256. Only the envelope shape
 * and validation live here (pure and testable); the actual crypto calls are in
 * `service/BackupCrypto.ets` because they need CryptoArchitectureKit.
 *
 * Nothing in this module touches the password. The password, derived key and
 * plaintext are never written to logs or preferences.
 */

import { SESSION_EXPORT_APP, SESSION_EXPORT_VERSION } from './SessionExport';
import { backupFileName } from './Backup';

export const ENCRYPTED_BACKUP_KIND: string = 'backup-encrypted';
export const BACKUP_CIPHER: string = 'AES-256-GCM';
export const BACKUP_KDF: string = 'PBKDF2-HMAC-SHA256';
export const BACKUP_ITERATIONS: number = 120000;
export const BACKUP_MIN_ITERATIONS: number = 10000;
export const BACKUP_MAX_ITERATIONS: number = 1000000;
export const BACKUP_SALT_BYTES: number = 16;
export const BACKUP_IV_BYTES: number = 12;
export const BACKUP_TAG_BYTES: number = 16;
export const BACKUP_MIN_PASSWORD: number = 6;

export interface EncryptedBackupEnvelope {
  app: string;
  version: number;
  kind: string;
  exportedAt: string;
  exportedOn: string;
  cipher: string;
  kdf: string;
  iterations: number;
  salt: string;
  iv: string;
  payload: string;
}

interface RawEncryptedRoot {
  app?: string;
  version?: number;
  kind?: string;
  exportedAt?: string;
  exportedOn?: string;
  cipher?: string;
  kdf?: string;
  iterations?: number;
  salt?: string;
  iv?: string;
  payload?: string;
}

function isBase64(value: string): boolean {
  return value.length > 0 && /^[A-Za-z0-9+/]+={0,2}$/.test(value);
}

/** `minis-backup-2026-11-08-...-enc.json` next to the plain backup name. */
export function encryptedBackupFileName(now: Date): string {
  return backupFileName(now).replace(/\.json$/, '-enc.json');
}

export function buildEncryptedEnvelope(
  exportedAt: string,
  exportedOn: string,
  salt: string,
  iv: string,
  payload: string
): EncryptedBackupEnvelope {
  return {
    app: SESSION_EXPORT_APP,
    version: SESSION_EXPORT_VERSION,
    kind: ENCRYPTED_BACKUP_KIND,
    exportedAt: exportedAt,
    exportedOn: exportedOn,
    cipher: BACKUP_CIPHER,
    kdf: BACKUP_KDF,
    iterations: BACKUP_ITERATIONS,
    salt: salt,
    iv: iv,
    payload: payload
  };
}

/**
 * Strict validation of an encrypted-backup header. Returns null for anything
 * that is not our envelope, so callers can treat corrupt files as a normal
 * import failure rather than crashing.
 */
export function parseEncryptedBackup(text: string): EncryptedBackupEnvelope | null {
  let root: RawEncryptedRoot;
  try {
    root = JSON.parse(text) as RawEncryptedRoot;
  } catch (e) {
    return null;
  }
  if (root === null || root === undefined) {
    return null;
  }
  if (root.app !== SESSION_EXPORT_APP || root.version !== SESSION_EXPORT_VERSION ||
    root.kind !== ENCRYPTED_BACKUP_KIND ||
    root.cipher !== BACKUP_CIPHER || root.kdf !== BACKUP_KDF) {
    return null;
  }
  const iterations: number = typeof root.iterations === 'number' ? root.iterations : 0;
  if (!Number.isInteger(iterations) || iterations < BACKUP_MIN_ITERATIONS ||
    iterations > BACKUP_MAX_ITERATIONS) {
    return null;
  }
  const salt: string = typeof root.salt === 'string' ? root.salt : '';
  const iv: string = typeof root.iv === 'string' ? root.iv : '';
  const payload: string = typeof root.payload === 'string' ? root.payload : '';
  // A GCM payload is ciphertext plus a 16-byte tag, so base64 must be long
  // enough to hold at least the tag.
  if (!isBase64(salt) || !isBase64(iv) || !isBase64(payload) ||
    payload.length < 24) {
    return null;
  }
  return {
    app: SESSION_EXPORT_APP,
    version: SESSION_EXPORT_VERSION,
    kind: ENCRYPTED_BACKUP_KIND,
    exportedAt: typeof root.exportedAt === 'string' ? root.exportedAt : '',
    exportedOn: typeof root.exportedOn === 'string' ? root.exportedOn : '',
    cipher: BACKUP_CIPHER,
    kdf: BACKUP_KDF,
    iterations: iterations,
    salt: salt,
    iv: iv,
    payload: payload
  };
}

export function isEncryptedBackup(text: string): boolean {
  return parseEncryptedBackup(text) !== null;
}
