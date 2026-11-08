import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

const MAX_ATTACHMENT_BYTES: number = 10 * 1024 * 1024;
const ATTACHMENT_PREFIX: string = 'attachment:';

export interface AttachmentInfo {
  /** File name inside the attachments directory. */
  name: string;
  mimeType: string;
}

/**
 * Images the user attaches to a message are copied into the app sandbox on
 * pick, so the system picker URI (which can expire) never has to survive a
 * restart. Messages store `attachment:<file name>` and the file is turned into
 * a data URL only when a request is built.
 */
export class AttachmentStore {
  private static dir: string = '';
  private static cache: Map<string, string> = new Map();

  static init(dir: string): void {
    AttachmentStore.dir = dir;
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
    } catch (e) {
      // First save reports the problem.
    }
  }

  static isAttachmentUri(uri: string): boolean {
    return uri.startsWith(ATTACHMENT_PREFIX);
  }

  static nameFromUri(uri: string): string {
    return uri.startsWith(ATTACHMENT_PREFIX)
      ? uri.substring(ATTACHMENT_PREFIX.length)
      : uri;
  }

  static absolutePath(name: string): string {
    return AttachmentStore.dir + '/' + AttachmentStore.nameFromUri(name);
  }

  static uriFor(name: string): string {
    return ATTACHMENT_PREFIX + name;
  }

  private static mimeFor(ext: string): string {
    if (ext === 'png') {
      return 'image/png';
    }
    if (ext === 'jpg' || ext === 'jpeg') {
      return 'image/jpeg';
    }
    if (ext === 'webp') {
      return 'image/webp';
    }
    if (ext === 'gif') {
      return 'image/gif';
    }
    if (ext === 'bmp') {
      return 'image/bmp';
    }
    return '';
  }

  private static extensionOf(uri: string): string {
    let path: string = uri;
    const query: number = path.indexOf('?');
    if (query >= 0) {
      path = path.substring(0, query);
    }
    const dot: number = path.lastIndexOf('.');
    if (dot < 0 || dot === path.length - 1) {
      return '';
    }
    return path.substring(dot + 1).toLowerCase();
  }

  /** Copies a picked image into the sandbox; null when it is not usable. */
  static async saveFromUri(sourceUri: string): Promise<AttachmentInfo | null> {
    if (AttachmentStore.dir.length === 0 || sourceUri.trim().length === 0) {
      return null;
    }
    const ext: string = AttachmentStore.extensionOf(sourceUri);
    const mime: string = AttachmentStore.mimeFor(ext);
    if (mime.length === 0) {
      return null;
    }
    try {
      const stat = fs.statSync(sourceUri);
      if (!stat.isFile() || stat.size <= 0 || stat.size > MAX_ATTACHMENT_BYTES) {
        return null;
      }
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      const source = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY);
      try {
        fs.readSync(source.fd, buffer);
      } finally {
        fs.closeSync(source);
      }
      const name: string = util.generateRandomUUID(true) + '.' + ext;
      const target = fs.openSync(AttachmentStore.absolutePath(name),
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(target.fd, buffer);
      } finally {
        fs.closeSync(target);
      }
      return { name: name, mimeType: mime };
    } catch (e) {
      return null;
    }
  }

  /** Data URL used by the multimodal request builder. Empty on failure. */
  static dataUrl(uri: string, mimeType: string): string {
    const name: string = AttachmentStore.nameFromUri(uri);
    const cached: string | undefined = AttachmentStore.cache.get(name);
    if (cached !== undefined) {
      return cached;
    }
    let mime: string = mimeType;
    if (mime.length === 0) {
      mime = AttachmentStore.mimeFor(AttachmentStore.extensionOf(name));
    }
    if (mime.length === 0) {
      return '';
    }
    try {
      const stat = fs.statSync(AttachmentStore.absolutePath(name));
      if (!stat.isFile() || stat.size <= 0 || stat.size > MAX_ATTACHMENT_BYTES) {
        return '';
      }
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      const file = fs.openSync(AttachmentStore.absolutePath(name), fs.OpenMode.READ_ONLY);
      try {
        fs.readSync(file.fd, buffer);
      } finally {
        fs.closeSync(file);
      }
      const encoded: string = new util.Base64Helper()
        .encodeToStringSync(new Uint8Array(buffer));
      const url: string = 'data:' + mime + ';base64,' + encoded;
      AttachmentStore.cache.set(name, url);
      return url;
    } catch (e) {
      return '';
    }
  }
}
