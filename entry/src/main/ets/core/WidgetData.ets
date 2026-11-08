/**
 * Data shown by the home-screen service card (2x2). The main app publishes a
 * small snapshot after session changes; the form extension reads it whenever
 * the card is added or refreshed. Kept pure so parsing/clipping is testable.
 */

export interface WidgetSnapshot {
  title: string;
  body: string;
  /** Short status such as `生成中`; empty when idle. */
  hint: string;
  /** Epoch ms of the last publish; 0 when never published. */
  updatedAt: number;
}

export function defaultWidgetSnapshot(): WidgetSnapshot {
  return {
    title: 'Minis',
    body: '打开应用开始新对话',
    hint: '',
    updatedAt: 0
  };
}

/** Flatten newlines and clip, so a card excerpt never contains line breaks. */
export function widgetExcerpt(text: string, limit: number): string {
  const flat: string = text.replace(/\s+/g, ' ').trim();
  if (flat.length <= limit) {
    return flat;
  }
  return flat.substring(0, limit) + '…';
}

export function parseWidgetSnapshot(json: string): WidgetSnapshot | null {
  if (json.length === 0) {
    return null;
  }
  let raw: WidgetSnapshot;
  try {
    raw = JSON.parse(json) as WidgetSnapshot;
  } catch (e) {
    return null;
  }
  if (raw === null || raw === undefined || typeof raw !== 'object') {
    return null;
  }
  const fallback: WidgetSnapshot = defaultWidgetSnapshot();
  return {
    title: typeof raw.title === 'string' && raw.title.length > 0 ? raw.title : fallback.title,
    body: typeof raw.body === 'string' && raw.body.length > 0 ? raw.body : fallback.body,
    hint: typeof raw.hint === 'string' ? raw.hint : '',
    updatedAt: typeof raw.updatedAt === 'number' && raw.updatedAt > 0 ? raw.updatedAt : 0
  };
}

export function widgetSnapshotJson(snapshot: WidgetSnapshot): string {
  return JSON.stringify(snapshot);
}
