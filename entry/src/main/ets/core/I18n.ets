/**
 * Localization catalog.
 *
 * Source strings are Simplified Chinese literals; `t()` looks them up in the
 * catalog for the active language and falls back to English and then to the
 * source text. Keeping the Chinese source as the key means new strings are
 * usable immediately and a missing translation never shows an empty label.
 */

export const I18N_DEFAULT_LANGUAGE: string = 'zh-Hans';
export const I18N_FALLBACK_LANGUAGE: string = 'en';

export interface I18nLanguage {
  code: string;
  /** Name in its own language, shown in the picker. */
  label: string;
}

/** The same 18 locales OpenMinis ships. */
export const I18N_LANGUAGES: I18nLanguage[] = [
  { code: 'zh-Hans', label: '简体中文' },
  { code: 'zh-Hant', label: '繁體中文' },
  { code: 'en', label: 'English' },
  { code: 'ja', label: '日本語' },
  { code: 'ko', label: '한국어' },
  { code: 'de', label: 'Deutsch' },
  { code: 'fr', label: 'Français' },
  { code: 'es', label: 'Español' },
  { code: 'pt-BR', label: 'Português (Brasil)' },
  { code: 'ru', label: 'Русский' },
  { code: 'th', label: 'ไทย' },
  { code: 'id', label: 'Bahasa Indonesia' },
  { code: 'ms', label: 'Bahasa Melayu' },
  { code: 'tr', label: 'Türkçe' },
  { code: 'pl', label: 'Polski' },
  { code: 'ro', label: 'Română' },
  { code: 'hr', label: 'Hrvatski' },
  { code: 'fil', label: 'Filipino' }
];

const catalogs: Map<string, Record<string, string>> = new Map();
let activeLanguage: string = I18N_DEFAULT_LANGUAGE;
let activeCatalog: Record<string, string> = {};
let fallbackCatalog: Record<string, string> = {};

/** Map any BCP-47 tag the system may report onto one of our 18 locales. */
export function normalizeI18nLanguage(raw: string): string {
  const value: string = raw.trim().toLowerCase();
  if (value.length === 0) {
    return I18N_DEFAULT_LANGUAGE;
  }
  if (value.indexOf('zh') === 0) {
    if (value.indexOf('hant') >= 0 || value === 'zh-tw' || value === 'zh-hk' ||
      value === 'zh-mo') {
      return 'zh-Hant';
    }
    return 'zh-Hans';
  }
  if (value.indexOf('pt') === 0) {
    return 'pt-BR';
  }
  if (value === 'tl' || value === 'fil-ph') {
    return 'fil';
  }
  if (value === 'in') {
    return 'id';
  }
  for (let i = 0; i < I18N_LANGUAGES.length; i++) {
    const code: string = I18N_LANGUAGES[i].code;
    if (value === code.toLowerCase() || value.indexOf(code.toLowerCase() + '-') === 0) {
      return code;
    }
  }
  return I18N_DEFAULT_LANGUAGE;
}

export function i18nLanguageLabel(code: string): string {
  const normalized: string = normalizeI18nLanguage(code);
  for (let i = 0; i < I18N_LANGUAGES.length; i++) {
    if (I18N_LANGUAGES[i].code === normalized) {
      return I18N_LANGUAGES[i].label;
    }
  }
  return normalized;
}

export function registerI18nCatalog(language: string,
  catalog: Record<string, string>): void {
  const normalized: string = normalizeI18nLanguage(language);
  catalogs.set(normalized, catalog);
  if (normalized === I18N_FALLBACK_LANGUAGE) {
    fallbackCatalog = catalog;
  }
  if (normalized === activeLanguage) {
    activeCatalog = catalog;
  }
}

export function selectI18nLanguage(language: string): void {
  activeLanguage = normalizeI18nLanguage(language);
  const catalog: Record<string, string> | undefined = catalogs.get(activeLanguage);
  activeCatalog = catalog === undefined ? {} : catalog;
  if (fallbackCatalog === undefined) {
    fallbackCatalog = {};
  }
}

export function activeI18nLanguage(): string {
  return activeLanguage;
}

export function hasI18nCatalog(language: string): boolean {
  return catalogs.has(normalizeI18nLanguage(language));
}

/**
 * Every loaded translation of one source string, plus the source itself.
 * Used to recognise content persisted before a language switch.
 */
export function i18nVariants(text: string): string[] {
  const out: string[] = [text];
  catalogs.forEach((catalog: Record<string, string>) => {
    const value: string | undefined = catalog[text];
    if (value !== undefined && value.length > 0 && out.indexOf(value) < 0) {
      out.push(value);
    }
  });
  return out;
}

/** Translate one Chinese source string. */
export function t(text: string): string {
  if (activeLanguage === I18N_DEFAULT_LANGUAGE || text.length === 0) {
    return text;
  }
  const direct: string | undefined = activeCatalog[text];
  if (direct !== undefined) {
    return direct;
  }
  const fallback: string | undefined = fallbackCatalog[text];
  if (fallback !== undefined) {
    return fallback;
  }
  return text;
}
