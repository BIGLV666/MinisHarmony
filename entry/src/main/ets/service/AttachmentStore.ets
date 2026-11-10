import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import {
  BROWSER_ARTIFACT_DIR,
  MINIS_BROWSER,
  MINIS_WORKSPACE,
  MinisResource,
  parseMinisResource
} from '../core/MinisResource';

const MAX_ATTACHMENT_BYTES: number = 10 * 1024 * 1024;
const MAX_VIDEO_BYTES: number = 100 * 1024 * 1024;
const MAX_AUDIO_BYTES: number = 20 * 1024 * 1024;
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

  /** Parent directory of the attachment directory, where `workspace` lives. */
  private static filesRoot(): string {
    const cut: number = AttachmentStore.dir.lastIndexOf('/');
    return cut < 0 ? AttachmentStore.dir : AttachmentStore.dir.substring(0, cut);
  }

  /**
   * Resolve either an attachment name/URI or a `minis://` resource link to an
   * absolute path. Tool results use `minis://workspace` and `minis://browser`;
   * generated images and user photos use `attachment:<name>`.
   */
  static imagePath(uri: string): string {
    if (uri.toLowerCase().indexOf('minis://') === 0) {
      const resource: MinisResource | null = parseMinisResource(uri);
      if (resource !== null) {
        if (resource.scope === MINIS_WORKSPACE) {
          return AttachmentStore.filesRoot() + '/workspace/' + resource.path;
        }
        if (resource.scope === MINIS_BROWSER) {
          return AttachmentStore.filesRoot() + '/workspace/' +
            BROWSER_ARTIFACT_DIR + '/' + resource.path;
        }
        return AttachmentStore.dir + '/' + resource.path;
      }
    }
    // Historical tool results stored workspace-relative paths without a
    // scheme (for example `.minis-browser/shot-…`); prefer the workspace copy
    // when it exists, otherwise treat the value as an attachment name.
    const plain: string = AttachmentStore.nameFromUri(uri);
    if (plain.indexOf('/') >= 0) {
      const candidate: string = AttachmentStore.filesRoot() + '/workspace/' + plain;
      try {
        if (fs.accessSync(candidate)) {
          return candidate;
        }
      } catch (e) {
      }
    }
    return AttachmentStore.absolutePath(uri);
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
    if (ext === 'mp4') {
      return 'video/mp4';
    }
    if (ext === 'webm') {
      return 'video/webm';
    }
    if (ext === 'mov') {
      return 'video/quicktime';
    }
    if (ext === 'm4v') {
      return 'video/x-m4v';
    }
    if (ext === 'mkv') {
      return 'video/x-matroska';
    }
    if (ext === 'mp3') {
      return 'audio/mpeg';
    }
    if (ext === 'm4a') {
      return 'audio/mp4';
    }
    if (ext === 'wav') {
      return 'audio/wav';
    }
    if (ext === 'ogg') {
      return 'audio/ogg';
    }
    if (ext === 'aac') {
      return 'audio/aac';
    }
    if (ext === 'flac') {
      return 'audio/flac';
    }
    return '';
  }

  /** Per-kind size caps: video files are much larger than photos. */
  private static maxBytesFor(mime: string): number {
    if (mime.startsWith('video/')) {
      return MAX_VIDEO_BYTES;
    }
    if (mime.startsWith('audio/')) {
      return MAX_AUDIO_BYTES;
    }
    return MAX_ATTACHMENT_BYTES;
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
      if (!stat.isFile() || stat.size <= 0 ||
        stat.size > AttachmentStore.maxBytesFor(mime)) {
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

  /**
   * Save bytes produced inside the app (e.g. a generated image). The caller
   * picks the extension because the bytes carry no file name.
   */
  static saveBytes(bytes: Uint8Array, ext: string): AttachmentInfo | null {
    if (AttachmentStore.dir.length === 0 || bytes.length === 0 ||
      bytes.length > MAX_ATTACHMENT_BYTES) {
      return null;
    }
    const mime: string = AttachmentStore.mimeFor(ext);
    if (mime.length === 0) {
      return null;
    }
    try {
      const name: string = util.generateRandomUUID(true) + '.' + ext;
      const exact: ArrayBuffer = new ArrayBuffer(bytes.length);
      new Uint8Array(exact).set(bytes);
      const file = fs.openSync(AttachmentStore.absolutePath(name),
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, exact);
      } finally {
        fs.closeSync(file);
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
    if (mime.length === 0 || mime.startsWith('video/') || mime.startsWith('audio/')) {
      // Only images travel as data URLs; media files stay as file parts.
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
