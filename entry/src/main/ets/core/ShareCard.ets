/**
 * Pure helpers for the single-turn share card: file naming and size guards.
 * The card itself is rendered offscreen by `components/ShareCardView.ets` and
 * encoded in `service/Screenshot.ets`.
 */

import { exportStamp, safeFileBase } from './MarkdownExport';
import { t } from './I18n';

/** One offscreen card should stay well below the renderer's texture limit. */
export const MAX_SHARE_BODY_CHARS: number = 12000;
export const MAX_SHARE_TOOL_LINES: number = 12;

export function shareCardFileName(title: string, now: Date): string {
  return safeFileBase(title) + '-' + exportStamp(now) + '-share.png';
}

function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

/** Absolute timestamp for the saved image; relative time would age badly. */
export function shareCardStamp(timestamp: number): string {
  const date: Date = new Date(timestamp);
  return date.getFullYear().toString() + '-' + pad2(date.getMonth() + 1) + '-' +
    pad2(date.getDate()) + ' ' + pad2(date.getHours()) + ':' +
    pad2(date.getMinutes());
}

/** Keep a whole turn on one image; note the cut instead of failing. */
export function shareCardBody(text: string): string {
  const trimmed: string = text.trim();
  if (trimmed.length <= MAX_SHARE_BODY_CHARS) {
    return trimmed;
  }
  return trimmed.substring(0, MAX_SHARE_BODY_CHARS) + t('\n\n…（内容过长，已截断）');
}

/** Tool rows on the card are a compact summary, not the full result text. */
export function shareCardToolLines(lines: string[]): string[] {
  if (lines.length <= MAX_SHARE_TOOL_LINES) {
    return lines.slice(0);
  }
  const out: string[] = lines.slice(0, MAX_SHARE_TOOL_LINES);
  out.push(t('…还有 ') + (lines.length - MAX_SHARE_TOOL_LINES).toString() +
    t(' 个工具调用'));
  return out;
}
