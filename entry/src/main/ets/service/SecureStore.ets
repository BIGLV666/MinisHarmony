import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';

const ALIAS_API_KEY: string = 'MinisHarmony.apiKey';
const ALIAS_SANDBOX_TOKEN: string = 'MinisHarmony.sandboxToken';

const encoder: util.TextEncoder = new util.TextEncoder();
const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');

function encode(value: string): Uint8Array {
  return encoder.encodeInto(value);
}

function decode(value: Uint8Array): string {
  return decoder.decodeToString(value);
}

/**
 * API Key and remote sandbox token in the system Asset Store.
 *
 * Asset Store Kit encrypts values at rest and ties them to the device's lock
 * screen. It can fail on devices without a lock screen or when the service is
 * unavailable; every method then reports failure and the caller falls back to
 * preferences, so the app stays usable. Callers must not log secrets.
 */
export class SecureStore {
  private static available: boolean = false;

  static isAvailable(): boolean {
    return SecureStore.available;
  }

  static apiKeyAlias(): string {
    return ALIAS_API_KEY;
  }

  static sandboxTokenAlias(): string {
    return ALIAS_SANDBOX_TOKEN;
  }

  /** Returns '' when the alias is unset, or null when the kit is unavailable. */
  static async get(alias: string): Promise<string | null> {
    try {
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, encode(alias));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const rows: Array<asset.AssetMap> = await asset.query(query);
      SecureStore.available = true;
      if (rows.length === 0) {
        return '';
      }
      const secret: asset.Value | undefined = rows[0].get(asset.Tag.SECRET);
      if (secret === undefined) {
        return '';
      }
      return decode(secret as Uint8Array);
    } catch (e) {
      return null;
    }
  }

  /** Upsert. Empty value removes the entry. Returns false when unavailable. */
  static async set(alias: string, value: string): Promise<boolean> {
    try {
      await SecureStore.remove(alias);
      if (value.length === 0) {
        return true;
      }
      const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      attributes.set(asset.Tag.ALIAS, encode(alias));
      attributes.set(asset.Tag.SECRET, encode(value));
      attributes.set(
        asset.Tag.ACCESSIBILITY,
        asset.Accessibility.DEVICE_FIRST_UNLOCKED
      );
      await asset.add(attributes);
      SecureStore.available = true;
      return true;
    } catch (e) {
      return false;
    }
  }

  static async remove(alias: string): Promise<boolean> {
    try {
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, encode(alias));
      await asset.remove(query);
      return true;
    } catch (e) {
      // NOT_FOUND is the common case when clearing an alias never written.
      return false;
    }
  }
}
