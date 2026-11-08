import { fileIo as fs } from '@kit.CoreFileKit';
import {
  MEMORY_CONTEXT_CHARS,
  MemoryFile,
  buildMemoryContext,
  dayKey,
  memoryEntry,
  oneLine,
  searchMemoryFiles
} from '../core/Memory';

const GLOBAL_FILE: string = 'GLOBAL.md';
const DEFAULT_DAYS: number = 7;
const CONTEXT_DAYS: number = 3;
const CACHE_MS: number = 3000;

/**
 * Device-local memory under `filesDir/memory`. It sits outside the workspace
 * on purpose: the model reaches it through `memory_write` / `memory_get`, not
 * through file tools, so a workspace jail cannot be used to read it.
 */
export class MemoryStore {
  private static root: string = '';
  private static cachedContext: string = '';
  private static cacheAt: number = 0;

  static init(root: string): void {
    MemoryStore.root = root;
    try {
      if (!fs.accessSync(root)) {
        fs.mkdirSync(root, true);
      }
    } catch (e) {
      // First write reports the failure.
    }
  }

  static isReady(): boolean {
    return MemoryStore.root.length > 0;
  }

  private static readIfExists(name: string): string {
    if (MemoryStore.root.length === 0) {
      return '';
    }
    const path: string = MemoryStore.root + '/' + name;
    try {
      if (!fs.accessSync(path)) {
        return '';
      }
      return fs.readTextSync(path);
    } catch (e) {
      return '';
    }
  }

  /** Daily files newest-first, capped at `days`. */
  private static dailyNames(days: number): string[] {
    if (MemoryStore.root.length === 0 || days <= 0) {
      return [];
    }
    let names: string[] = [];
    try {
      names = fs.listFileSync(MemoryStore.root);
    } catch (e) {
      return [];
    }
    const daily: string[] = [];
    for (let i = 0; i < names.length; i++) {
      const name: string = names[i];
      if (name !== GLOBAL_FILE && name.length >= 13 && name.endsWith('.md')) {
        daily.push(name);
      }
    }
    daily.sort();
    const out: string[] = [];
    for (let i = daily.length - 1; i >= 0 && out.length < days; i--) {
      out.push(daily[i]);
    }
    return out;
  }

  /** Recent daily notes followed by GLOBAL.md (the long-lived profile). */
  static files(days: number): MemoryFile[] {
    const out: MemoryFile[] = [];
    const names: string[] = MemoryStore.dailyNames(days);
    for (let i = 0; i < names.length; i++) {
      const text: string = MemoryStore.readIfExists(names[i]);
      if (text.trim().length > 0) {
        out.push({ name: names[i], text: text });
      }
    }
    const global: string = MemoryStore.readIfExists(GLOBAL_FILE);
    if (global.trim().length > 0) {
      out.push({ name: GLOBAL_FILE, text: global });
    }
    return out;
  }

  /** System-prompt block; cached briefly because it is read every model turn. */
  static context(): string {
    const now: number = Date.now();
    if (now - MemoryStore.cacheAt < CACHE_MS) {
      return MemoryStore.cachedContext;
    }
    MemoryStore.cachedContext = buildMemoryContext(
      MemoryStore.files(CONTEXT_DAYS), MEMORY_CONTEXT_CHARS
    );
    MemoryStore.cacheAt = now;
    return MemoryStore.cachedContext;
  }

  static write(content: string): string {
    if (!MemoryStore.isReady()) {
      return '记忆目录未初始化。';
    }
    const clean: string = oneLine(content);
    if (clean.length === 0) {
      return '内容为空，没有写入记忆。';
    }
    const now: Date = new Date();
    const name: string = dayKey(now) + '.md';
    const path: string = MemoryStore.root + '/' + name;
    try {
      const file = fs.openSync(
        path,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.APPEND
      );
      try {
        fs.writeSync(file.fd, memoryEntry(now, content) + '\n');
      } finally {
        fs.closeSync(file);
      }
      MemoryStore.cacheAt = 0;
      return '已写入记忆（' + name + '）：' + clean;
    } catch (e) {
      const error: Error = e as Error;
      return '写入记忆失败：' + error.message;
    }
  }

  static search(query: string, days: number, limit: number): string {
    if (!MemoryStore.isReady()) {
      return '记忆目录未初始化。';
    }
    const window: number = days > 0 ? days : DEFAULT_DAYS;
    return searchMemoryFiles(MemoryStore.files(window), query, limit);
  }

  static clearDaily(): number {
    if (!MemoryStore.isReady()) {
      return 0;
    }
    const names: string[] = MemoryStore.dailyNames(1000);
    let removed: number = 0;
    for (let i = 0; i < names.length; i++) {
      try {
        fs.unlinkSync(MemoryStore.root + '/' + names[i]);
        removed++;
      } catch (e) {
        // Keep going; partial deletion is still useful.
      }
    }
    MemoryStore.cacheAt = 0;
    return removed;
  }
}
