import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { i18n } from '@kit.LocalizationKit';
import { util } from '@kit.ArkTS';
import {
  I18N_DEFAULT_LANGUAGE,
  activeI18nLanguage,
  normalizeI18nLanguage,
  registerI18nCatalog,
  selectI18nLanguage
} from '../core/I18n';

const STORE_NAME: string = 'minis_i18n_v1';
const KEY_LANGUAGE: string = 'language';
export const I18N_VERSION_KEY: string = 'i18nVersion';

/**
 * Loads the per-language string catalog from `rawfile/i18n/` and persists the
 * user's choice. Catalogs are plain Chinese-to-translation maps, so a missing
 * entry falls back to English and then to the Chinese source in `core/I18n`.
 */
export class I18nService {
  private static loaded: Set<string> = new Set();
  private static store: preferences.Preferences | null = null;

  private static catalogPath(language: string): string {
    if (language === 'zh-Hant') {
      return 'i18n/zh-Hant.json';
    }
    return 'i18n/' + language + '.json';
  }

  private static loadCatalog(context: common.Context, language: string): void {
    if (language === I18N_DEFAULT_LANGUAGE || I18nService.loaded.has(language)) {
      return;
    }
    try {
      const bytes: Uint8Array =
        context.resourceManager.getRawFileContentSync(I18nService.catalogPath(language));
      const text: string = util.TextDecoder.create('utf-8').decodeToString(bytes);
      const parsed: Record<string, string> = JSON.parse(text) as Record<string, string>;
      registerI18nCatalog(language, parsed);
      I18nService.loaded.add(language);
    } catch (e) {
      // A missing or malformed catalog leaves the Chinese source visible.
      I18nService.loaded.add(language);
    }
  }

  /** Called from `EntryAbility.onCreate`, before the first page is built. */
  static init(context: common.Context): void {
    let language: string = I18N_DEFAULT_LANGUAGE;
    try {
      I18nService.store = preferences.getPreferencesSync(context, { name: STORE_NAME });
    } catch (e) {
      I18nService.store = null;
    }
    if (I18nService.store !== null) {
      try {
        const saved: preferences.ValueType = I18nService.store.getSync(KEY_LANGUAGE, '');
        if (typeof saved === 'string' && saved.length > 0) {
          language = normalizeI18nLanguage(saved as string);
        } else {
          language = normalizeI18nLanguage(i18n.getSystemLanguage());
        }
      } catch (e) {
        language = normalizeI18nLanguage(i18n.getSystemLanguage());
      }
    } else {
      language = normalizeI18nLanguage(i18n.getSystemLanguage());
    }
    I18nService.loadCatalog(context, 'en');
    I18nService.loadCatalog(context, language);
    selectI18nLanguage(language);
  }

  static current(): string {
    return activeI18nLanguage();
  }

  /** Switch immediately; `@StorageProp` on the pages rebuilds the UI. */
  static setLanguage(context: common.Context, language: string): void {
    const normalized: string = normalizeI18nLanguage(language);
    I18nService.loadCatalog(context, 'en');
    I18nService.loadCatalog(context, normalized);
    selectI18nLanguage(normalized);
    if (I18nService.store !== null) {
      try {
        I18nService.store.putSync(KEY_LANGUAGE, normalized);
        I18nService.store.flush();
      } catch (e) {
        // The session still switches even if persistence fails.
      }
    }
    AppStorage.setOrCreate<number>(I18N_VERSION_KEY, Date.now());
  }
}
