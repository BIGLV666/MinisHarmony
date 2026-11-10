import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import {
  BrowserDownloadEntry,
  BrowserHistoryEntry,
  parseDownloads,
  parseHistory,
  recordHistory,
  upsertDownload
} from '../core/BrowserHistory';
import { parseViewportSize } from '../core/BrowserViewport';

const STORE_NAME: string = 'minis_browser_store';
const KEY_HISTORY: string = 'history';
const KEY_DOWNLOADS: string = 'downloads';
const KEY_UA_PRESET: string = 'ua_preset';
const KEY_UA_CUSTOM: string = 'ua_custom';
const KEY_WIDE: string = 'wide_viewport';
const KEY_VIEWPORT_W: string = 'viewport_width';
const KEY_VIEWPORT_H: string = 'viewport_height';

/**
 * Local-only persistence for the browser's history, download records and
 * settings. Values are metadata; page content and cookies stay in ArkWeb.
 */
export class BrowserStore {
  private static store(context: common.Context): preferences.Preferences {
    const options: preferences.Options = { name: STORE_NAME };
    return preferences.getPreferencesSync(context, options);
  }

  private static readString(context: common.Context, key: string): string {
    try {
      const raw: preferences.ValueType = BrowserStore.store(context).getSync(key, '');
      return typeof raw === 'string' ? raw as string : '';
    } catch (e) {
      return '';
    }
  }

  private static writeString(context: common.Context, key: string, value: string): void {
    try {
      const store: preferences.Preferences = BrowserStore.store(context);
      store.putSync(key, value);
      store.flush().catch((error: Error) => {
      });
    } catch (e) {
    }
  }

  static history(context: common.Context): BrowserHistoryEntry[] {
    return parseHistory(BrowserStore.readString(context, KEY_HISTORY));
  }

  static recordHistory(context: common.Context, entry: BrowserHistoryEntry): BrowserHistoryEntry[] {
    const next: BrowserHistoryEntry[] =
      recordHistory(BrowserStore.history(context), entry);
    BrowserStore.writeString(context, KEY_HISTORY, JSON.stringify(next));
    return next;
  }

  static clearHistory(context: common.Context): void {
    BrowserStore.writeString(context, KEY_HISTORY, '');
  }

  static downloads(context: common.Context): BrowserDownloadEntry[] {
    return parseDownloads(BrowserStore.readString(context, KEY_DOWNLOADS));
  }

  static recordDownload(context: common.Context,
    entry: BrowserDownloadEntry): BrowserDownloadEntry[] {
    const next: BrowserDownloadEntry[] = upsertDownload(BrowserStore.downloads(context), entry);
    BrowserStore.writeString(context, KEY_DOWNLOADS, JSON.stringify(next));
    return next;
  }

  static clearDownloads(context: common.Context): void {
    BrowserStore.writeString(context, KEY_DOWNLOADS, '');
  }

  static uaPreset(context: common.Context): string {
    const value: string = BrowserStore.readString(context, KEY_UA_PRESET);
    return value.length > 0 ? value : 'default';
  }

  static customUserAgent(context: common.Context): string {
    return BrowserStore.readString(context, KEY_UA_CUSTOM);
  }

  static saveUserAgent(context: common.Context, preset: string, custom: string): void {
    BrowserStore.writeString(context, KEY_UA_PRESET, preset);
    BrowserStore.writeString(context, KEY_UA_CUSTOM, custom);
  }

  static wideViewport(context: common.Context): boolean {
    return BrowserStore.readString(context, KEY_WIDE) === '1';
  }

  static saveWideViewport(context: common.Context, wide: boolean): void {
    BrowserStore.writeString(context, KEY_WIDE, wide ? '1' : '0');
  }

  /** Custom page surface size in vp; 0 means fill the panel. */
  static viewportWidth(context: common.Context): number {
    return parseViewportSize(BrowserStore.readString(context, KEY_VIEWPORT_W));
  }

  static viewportHeight(context: common.Context): number {
    return parseViewportSize(BrowserStore.readString(context, KEY_VIEWPORT_H));
  }

  static saveViewport(context: common.Context, width: number, height: number): void {
    BrowserStore.writeString(context, KEY_VIEWPORT_W, width > 0 ? width.toString() : '');
    BrowserStore.writeString(context, KEY_VIEWPORT_H, height > 0 ? height.toString() : '');
  }
}

export const UA_MOBILE: string =
  'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
export const UA_DESKTOP: string =
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/** Empty string means "let ArkWeb use its built-in UA". */
export function userAgentFor(preset: string, custom: string): string {
  if (preset === 'mobile') {
    return UA_MOBILE;
  }
  if (preset === 'desktop') {
    return UA_DESKTOP;
  }
  if (preset === 'custom') {
    return custom.trim();
  }
  return '';
}
