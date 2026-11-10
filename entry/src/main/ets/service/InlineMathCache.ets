import { image } from '@kit.ImageKit';

/** One rendered inline formula, sized in physical pixels. */
export class InlineMathBitmap {
  pixelMap: image.PixelMap;
  widthPx: number;
  heightPx: number;

  constructor(pixelMap: image.PixelMap, widthPx: number, heightPx: number) {
    this.pixelMap = pixelMap;
    this.widthPx = widthPx;
    this.heightPx = heightPx;
  }
}

export type InlineMathCallback = (bitmap: InlineMathBitmap | null) => void;

/**
 * Renders one formula through the hidden KaTeX Web host. Resolving with null
 * means the caller keeps its Unicode fallback.
 */
export type InlineMathRenderer =
  (latex: string, fontSize: number, dark: boolean) => Promise<InlineMathBitmap>;

class InlineMathJob {
  key: string;
  latex: string;
  fontSize: number;
  dark: boolean;

  constructor(key: string, latex: string, fontSize: number, dark: boolean) {
    this.key = key;
    this.latex = latex;
    this.fontSize = fontSize;
    this.dark = dark;
  }
}

const MAX_CACHE_ENTRIES: number = 256;

/**
 * Process-wide cache and serial queue for inline formulas. OpenMinis renders
 * each inline formula with KaTeX in an offscreen WebView and shows the bitmap
 * in the text flow; ArkWeb has no inline math primitive, so the same pipeline
 * runs here on top of `webPageSnapshot`. Formulas repeat across messages, so
 * the cache matters more than the render time.
 */
export class InlineMathCache {
  private static renderer: InlineMathRenderer | null = null;
  private static cache: Map<string, InlineMathBitmap> = new Map();
  private static pending: Map<string, InlineMathCallback[]> = new Map();
  private static queue: InlineMathJob[] = [];
  private static busy: boolean = false;

  static keyFor(latex: string, fontSize: number, dark: boolean): string {
    return (dark ? 'd' : 'l') + ':' + fontSize.toFixed(1) + ':' + latex;
  }

  static get(key: string): InlineMathBitmap | null {
    const bitmap: InlineMathBitmap | undefined = InlineMathCache.cache.get(key);
    return bitmap !== undefined ? bitmap : null;
  }

  static setRenderer(renderer: InlineMathRenderer | null): void {
    InlineMathCache.renderer = renderer;
    if (renderer !== null) {
      InlineMathCache.pump();
    }
  }

  static request(latex: string, fontSize: number, dark: boolean,
    callback: InlineMathCallback): void {
    if (latex.trim().length === 0) {
      callback(null);
      return;
    }
    const key: string = InlineMathCache.keyFor(latex, fontSize, dark);
    const cached: InlineMathBitmap | undefined = InlineMathCache.cache.get(key);
    if (cached !== undefined) {
      callback(cached);
      return;
    }
    const waiting: InlineMathCallback[] | undefined = InlineMathCache.pending.get(key);
    if (waiting !== undefined) {
      waiting.push(callback);
      return;
    }
    InlineMathCache.pending.set(key, [callback]);
    InlineMathCache.queue.push(
      new InlineMathJob(key, latex, fontSize, dark));
    InlineMathCache.pump();
  }

  private static finish(key: string, bitmap: InlineMathBitmap | null): void {
    if (bitmap !== null) {
      InlineMathCache.cache.set(key, bitmap);
      InlineMathCache.trim();
    }
    const waiting: InlineMathCallback[] | undefined = InlineMathCache.pending.get(key);
    InlineMathCache.pending.delete(key);
    if (waiting === undefined) {
      return;
    }
    for (let i = 0; i < waiting.length; i++) {
      try {
        waiting[i](bitmap);
      } catch (error) {
        // A disposed component must not stall the queue.
      }
    }
  }

  private static trim(): void {
    if (InlineMathCache.cache.size <= MAX_CACHE_ENTRIES) {
      return;
    }
    const keys: string[] = Array.from(InlineMathCache.cache.keys());
    const overflow: number = InlineMathCache.cache.size - MAX_CACHE_ENTRIES;
    for (let i = 0; i < overflow && i < keys.length; i++) {
      // Drop the cache reference only. A visible ImageSpan may still hold the
      // PixelMap; releasing it here would blank that formula. GC reclaims it
      // once the last view and this map let go.
      InlineMathCache.cache.delete(keys[i]);
    }
  }

  private static pump(): void {
    if (InlineMathCache.busy || InlineMathCache.renderer === null ||
      InlineMathCache.queue.length === 0) {
      return;
    }
    const job: InlineMathJob = InlineMathCache.queue.shift() as InlineMathJob;
    const renderer: InlineMathRenderer = InlineMathCache.renderer as InlineMathRenderer;
    InlineMathCache.busy = true;
    renderer(job.latex, job.fontSize, job.dark).then((bitmap: InlineMathBitmap) => {
      InlineMathCache.busy = false;
      InlineMathCache.finish(job.key, bitmap);
      InlineMathCache.pump();
    }).catch(() => {
      InlineMathCache.busy = false;
      InlineMathCache.finish(job.key, null);
      InlineMathCache.pump();
    });
  }
}
