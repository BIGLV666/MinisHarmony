import { activeI18nLanguage, t } from '../core/I18n';
/** Presentation helpers shared by the list, header and message bubbles. */

/**
 * Month/day for older messages. Numeric order differs by locale, so this is
 * formatted from the active language instead of concatenating translated
 * fragments (which would yield e.g. "11Buwan8Araw").
 */
function shortMonthDay(month: number, day: number): string {
  const language: string = activeI18nLanguage();
  if (language === 'zh-Hans' || language === 'zh-Hant' || language === 'ja') {
    return month + '月' + day + '日';
  }
  if (language === 'ko') {
    return month + '월' + day + '일';
  }
  if (language === 'en' || language === 'fil') {
    return month + '/' + day;
  }
  if (language === 'de') {
    return day + '.' + month + '.';
  }
  if (language === 'hr') {
    return day + '. ' + month + '.';
  }
  return day + '/' + month;
}

export function formatRelative(timestamp: number): string {
  if (timestamp <= 0) {
    return '';
  }
  const now: number = Date.now();
  const diff: number = now - timestamp;
  if (diff < 60 * 1000) {
    return t('刚刚');
  }
  if (diff < 60 * 60 * 1000) {
    return Math.floor(diff / (60 * 1000)) + t(' 分钟前');
  }
  if (diff < 24 * 60 * 60 * 1000) {
    return Math.floor(diff / (60 * 60 * 1000)) + t(' 小时前');
  }
  if (diff < 48 * 60 * 60 * 1000) {
    return t('昨天');
  }
  const date: Date = new Date(timestamp);
  const month: number = date.getMonth() + 1;
  const day: number = date.getDate();
  return shortMonthDay(month, day);
}

export function titleFrom(text: string): string {
  const firstLine: string = text.trim().split('\n')[0].trim();
  if (firstLine.length === 0) {
    return t('新对话');
  }
  if (firstLine.length <= 26) {
    return firstLine;
  }
  return firstLine.substring(0, 26) + t('…');
}

/** Compact token count for headers and message footers. */
export function formatTokens(value: number): string {
  if (value >= 1000000) {
    return (value / 1000000).toFixed(1) + 'M';
  }
  if (value >= 1000) {
    return (value / 1000).toFixed(1) + 'k';
  }
  return Math.round(value).toString();
}

export function estimateTokens(text: string): number {
  // Rough display-only estimate: CJK ~1 token/char, Latin ~1 token/4 chars.
  let cjk: number = 0;
  let other: number = 0;
  for (let i = 0; i < text.length; i++) {
    const code: number = text.charCodeAt(i);
    if (code >= 0x2e80) {
      cjk++;
    } else {
      other++;
    }
  }
  return Math.ceil(cjk + other / 4);
}
