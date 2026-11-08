import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import {
  BACKUP_IV_BYTES,
  BACKUP_ITERATIONS,
  BACKUP_SALT_BYTES,
  BACKUP_TAG_BYTES,
  EncryptedBackupEnvelope,
  buildEncryptedEnvelope,
  parseEncryptedBackup
} from '../core/BackupCrypto';

const CIPHER_TRANSFORMATION: string = 'AES256|GCM|NoPadding';
const KDF_ALGORITHM: string = 'PBKDF2|SHA256';
const GCM_PARAMS_NAME: string = 'GcmParamsSpec';
const KEY_BYTES: number = 32;

const encoder: util.TextEncoder = new util.TextEncoder();
const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
const base64: util.Base64Helper = new util.Base64Helper();

export interface DecryptOutcome {
  ok: boolean;
  message: string;
  text: string;
}

function blob(data: Uint8Array): cryptoFramework.DataBlob {
  const value: cryptoFramework.DataBlob = { data: data };
  return value;
}

function gcmParams(iv: Uint8Array, tag: Uint8Array): cryptoFramework.GcmParamsSpec {
  const params: cryptoFramework.GcmParamsSpec = {
    algName: GCM_PARAMS_NAME,
    iv: blob(iv),
    aad: blob(new Uint8Array(0)),
    authTag: blob(tag)
  };
  return params;
}

async function deriveKey(password: string, salt: Uint8Array): Promise<cryptoFramework.SymKey> {
  const kdf: cryptoFramework.Kdf = cryptoFramework.createKdf(KDF_ALGORITHM);
  const spec: cryptoFramework.PBKDF2Spec = {
    algName: 'PBKDF2',
    password: password,
    salt: salt,
    iterations: BACKUP_ITERATIONS,
    keySize: KEY_BYTES
  };
  const secret: cryptoFramework.DataBlob = await kdf.generateSecret(spec);
  const generator: cryptoFramework.SymKeyGenerator =
    cryptoFramework.createSymKeyGenerator('AES256');
  return generator.convertKey(secret);
}

function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

function stamp(now: Date): string {
  const month: string = pad2(now.getMonth() + 1);
  const day: string = pad2(now.getDate());
  const hour: string = pad2(now.getHours());
  const minute: string = pad2(now.getMinutes());
  return now.getFullYear().toString() + '-' + month + '-' + day + ' ' + hour + ':' + minute;
}

/**
 * Encrypt a plain backup JSON string into the versioned envelope.
 * The password is only used to derive the key and is never stored.
 */
export async function encryptBackupText(
  plain: string,
  password: string,
  now: Date
): Promise<string> {
  const random: cryptoFramework.Random = cryptoFramework.createRandom();
  const salt: Uint8Array = random.generateRandomSync(BACKUP_SALT_BYTES).data;
  const iv: Uint8Array = random.generateRandomSync(BACKUP_IV_BYTES).data;
  const key: cryptoFramework.SymKey = await deriveKey(password, salt);
  const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher(CIPHER_TRANSFORMATION);
  await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, key,
    gcmParams(iv, new Uint8Array(BACKUP_TAG_BYTES)));
  // GCM: update() returns the ciphertext and doFinal(null) returns the tag.
  const sealed: cryptoFramework.DataBlob | null =
    await cipher.update(blob(encoder.encodeInto(plain)));
  const tagBlob: cryptoFramework.DataBlob | null = await cipher.doFinal(null);
  const body: Uint8Array = sealed === null ? new Uint8Array(0) : sealed.data;
  const tag: Uint8Array = tagBlob === null ? new Uint8Array(0) : tagBlob.data;
  if (tag.length !== BACKUP_TAG_BYTES) {
    throw new Error('无法获取 GCM 认证标签');
  }
  // Store ciphertext followed by the tag so the envelope has one payload field.
  const joined: Uint8Array = new Uint8Array(body.length + tag.length);
  joined.set(body, 0);
  joined.set(tag, body.length);
  const payload: string = base64.encodeToStringSync(joined);
  const envelope: EncryptedBackupEnvelope = buildEncryptedEnvelope(
    now.toISOString(), stamp(now),
    base64.encodeToStringSync(salt), base64.encodeToStringSync(iv), payload);
  return JSON.stringify(envelope, null, 2);
}

/**
 * Decrypt an encrypted backup. Any failure (wrong password, truncated file,
 * tampered bytes) reports the same message so the tag check is not a password
 * oracle.
 */
export async function decryptBackupText(
  raw: string,
  password: string
): Promise<DecryptOutcome> {
  const envelope: EncryptedBackupEnvelope | null = parseEncryptedBackup(raw);
  if (envelope === null) {
    return { ok: false, message: '不是有效的加密备份文件', text: '' };
  }
  try {
    const salt: Uint8Array = base64.decodeSync(envelope.salt);
    const iv: Uint8Array = base64.decodeSync(envelope.iv);
    const sealed: Uint8Array = base64.decodeSync(envelope.payload);
    if (sealed.length <= BACKUP_TAG_BYTES) {
      return { ok: false, message: '加密数据不完整', text: '' };
    }
    const body: Uint8Array = sealed.slice(0, sealed.length - BACKUP_TAG_BYTES);
    const tag: Uint8Array = sealed.slice(sealed.length - BACKUP_TAG_BYTES);
    const key: cryptoFramework.SymKey = await deriveKey(password, salt);
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher(CIPHER_TRANSFORMATION);
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, key, gcmParams(iv, tag));
    // The tag is verified by doFinal(null); update() yields the plaintext.
    const opened: cryptoFramework.DataBlob | null = await cipher.update(blob(body));
    const rest: cryptoFramework.DataBlob | null = await cipher.doFinal(null);
    const first: Uint8Array = opened === null ? new Uint8Array(0) : opened.data;
    const second: Uint8Array = rest === null ? new Uint8Array(0) : rest.data;
    const plainBytes: Uint8Array = new Uint8Array(first.length + second.length);
    plainBytes.set(first, 0);
    plainBytes.set(second, first.length);
    return {
      ok: true,
      message: '已解密',
      text: decoder.decodeToString(plainBytes)
    };
  } catch (e) {
    return { ok: false, message: '密码错误或文件已损坏', text: '' };
  }
}
