/**
 * WebDAV remote-backup helpers.
 *
 * HarmonyOS `http` only exposes the standard methods (no PROPFIND), so the
 * remote collection is not browsed. Each upload writes a dated snapshot plus a
 * stable `latest` object; restore reads `latest`. The payload is always the
 * password-encrypted backup envelope — never plaintext JSON.
 */

import { encryptedBackupFileName } from './BackupCrypto';

export const WEBDAV_LATEST_NAME: string = 'minis-backup-latest-enc.json';

/** Trim, require http(s), and drop trailing slashes. Empty means disabled. */
export function normalizeWebDavUrl(raw: string): string {
  let value: string = raw.trim();
  const lower: string = value.toLowerCase();
  if (lower.indexOf('http://') !== 0 && lower.indexOf('https://') !== 0) {
    return '';
  }
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  const schemeLength: number = value.toLowerCase().indexOf('http://') === 0 ? 7 : 8;
  return value.length > schemeLength ? value : '';
}

export function webDavFileUrl(base: string, name: string): string {
  const normalized: string = normalizeWebDavUrl(base);
  if (normalized.length === 0 || name.length === 0) {
    return '';
  }
  return normalized + '/' + name;
}

/** Dated snapshot first, then the `latest` alias restore depends on. */
export function webDavUploadTargets(base: string, now: Date): string[] {
  const targets: string[] = [];
  const dated: string = webDavFileUrl(base, encryptedBackupFileName(now));
  const latest: string = webDavFileUrl(base, WEBDAV_LATEST_NAME);
  if (dated.length > 0) {
    targets.push(dated);
  }
  if (latest.length > 0 && latest !== dated) {
    targets.push(latest);
  }
  return targets;
}
