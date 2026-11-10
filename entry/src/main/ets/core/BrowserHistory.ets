/**
 * Browser history and download records for the in-app browser.
 *
 * OpenMinis keeps both lists locally (URL/title/time for history, name/path/
 * size for downloads) and never uploads them. These helpers are pure so the
 * merge rules are testable without preferences; `service/BrowserStore.ets`
 * persists the JSON blobs.
 */
export interface BrowserHistoryEntry {
  url: string;
  title: string;
  /** Epoch ms of the last visit. */
  at: number;
}

export interface BrowserDownloadEntry {
  name: string;
  path: string;
  /** Epoch ms when the download finished (or failed). */
  at: number;
  bytes: number;
  ok: boolean;
}

export const HISTORY_LIMIT: number = 200;
export const DOWNLOAD_LIMIT: number = 100;

function isWebUrl(url: string): boolean {
  return url.startsWith('http://') || url.startsWith('https://');
}

export function parseHistory(raw: string): BrowserHistoryEntry[] {
  const result: BrowserHistoryEntry[] = [];
  if (raw.length === 0) {
    return result;
  }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(raw) as Object;
  } catch (e) {
    return result;
  }
  if (!Array.isArray(parsed)) {
    return result;
  }
  const items: Object[] = parsed as Object[];
  for (let i = 0; i < items.length && result.length < HISTORY_LIMIT; i++) {
    const item: BrowserHistoryEntry = items[i] as BrowserHistoryEntry;
    if (item === null || item === undefined || typeof item.url !== 'string' ||
      !isWebUrl(item.url)) {
      continue;
    }
    const title: string = typeof item.title === 'string' ? item.title : '';
    const at: number = typeof item.at === 'number' && item.at > 0 ? item.at : 0;
    result.push({ url: item.url, title: title, at: at });
  }
  return result;
}

/**
 * Prepend a visit, replacing any earlier visit to the same URL so the list
 * behaves like a "most recent first" set rather than a full navigation log.
 * Non-web schemes (file://, data:) are not recorded.
 */
export function recordHistory(list: BrowserHistoryEntry[], entry: BrowserHistoryEntry,
  limit: number = HISTORY_LIMIT): BrowserHistoryEntry[] {
  if (!isWebUrl(entry.url)) {
    return list;
  }
  const next: BrowserHistoryEntry[] = [];
  next.push({
    url: entry.url,
    title: entry.title.length > 0 ? entry.title : entry.url,
    at: entry.at
  });
  for (let i = 0; i < list.length && next.length < limit; i++) {
    if (list[i].url !== entry.url) {
      next.push(list[i]);
    }
  }
  return next;
}

/** Case-insensitive match over title and URL. */
export function filterHistory(list: BrowserHistoryEntry[], keyword: string): BrowserHistoryEntry[] {
  const trimmed: string = keyword.trim().toLowerCase();
  if (trimmed.length === 0) {
    return list;
  }
  const result: BrowserHistoryEntry[] = [];
  for (let i = 0; i < list.length; i++) {
    const item: BrowserHistoryEntry = list[i];
    if (item.title.toLowerCase().indexOf(trimmed) >= 0 ||
      item.url.toLowerCase().indexOf(trimmed) >= 0) {
      result.push(item);
    }
  }
  return result;
}

export function parseDownloads(raw: string): BrowserDownloadEntry[] {
  const result: BrowserDownloadEntry[] = [];
  if (raw.length === 0) {
    return result;
  }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(raw) as Object;
  } catch (e) {
    return result;
  }
  if (!Array.isArray(parsed)) {
    return result;
  }
  const items: Object[] = parsed as Object[];
  for (let i = 0; i < items.length && result.length < DOWNLOAD_LIMIT; i++) {
    const item: BrowserDownloadEntry = items[i] as BrowserDownloadEntry;
    if (item === null || item === undefined || typeof item.path !== 'string' ||
      item.path.length === 0) {
      continue;
    }
    result.push({
      name: typeof item.name === 'string' && item.name.length > 0 ? item.name : item.path,
      path: item.path,
      at: typeof item.at === 'number' && item.at > 0 ? item.at : 0,
      bytes: typeof item.bytes === 'number' && item.bytes > 0 ? item.bytes : 0,
      ok: item.ok === true
    });
  }
  return result;
}

/** Newest first, one row per destination path. */
export function upsertDownload(list: BrowserDownloadEntry[], entry: BrowserDownloadEntry,
  limit: number = DOWNLOAD_LIMIT): BrowserDownloadEntry[] {
  const next: BrowserDownloadEntry[] = [];
  next.push(entry);
  for (let i = 0; i < list.length && next.length < limit; i++) {
    if (list[i].path !== entry.path) {
      next.push(list[i]);
    }
  }
  return next;
}

export function formatBytes(bytes: number): string {
  if (bytes <= 0) {
    return '—';
  }
  if (bytes < 1024) {
    return bytes.toString() + ' B';
  }
  if (bytes < 1024 * 1024) {
    return (bytes / 1024).toFixed(1) + ' KB';
  }
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}
