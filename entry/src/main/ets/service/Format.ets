/** Presentation helpers shared by the list, header and message bubbles. */

export function formatRelative(timestamp: number): string {
  if (timestamp <= 0) {
    return '';
  }
  const now: number = Date.now();
  const diff: number = now - timestamp;
  if (diff < 60 * 1000) {
    return '刚刚';
  }
  if (diff < 60 * 60 * 1000) {
    return Math.floor(diff / (60 * 1000)) + ' 分钟前';
  }
  if (diff < 24 * 60 * 60 * 1000) {
    return Math.floor(diff / (60 * 60 * 1000)) + ' 小时前';
  }
  if (diff < 48 * 60 * 60 * 1000) {
    return '昨天';
  }
  const date: Date = new Date(timestamp);
  const month: number = date.getMonth() + 1;
  const day: number = date.getDate();
  return month + '月' + day + '日';
}

export function titleFrom(text: string): string {
  const firstLine: string = text.trim().split('\n')[0].trim();
  if (firstLine.length === 0) {
    return '新对话';
  }
  if (firstLine.length <= 26) {
    return firstLine;
  }
  return firstLine.substring(0, 26) + '…';
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
