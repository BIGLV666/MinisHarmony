import { fileIo as fs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import {
  BrowserHandler,
  DeviceToolsHandler,
  ImageGenHandler,
  ImageGenRequest,
  SubagentHandler,
  SubagentRequest,
  ToolDefinition,
  ToolResult,
  ToolRuntime
} from '../core/ToolTypes';
import { builtinToolDefinitions, isToolDisabled } from '../core/ToolCatalog';
import {
  normalizeRelativePath,
  resolveWorkspacePath,
  truncateText
} from '../core/Workspace';
import { EditOutcome, applyExactEdit } from '../core/EditPatch';
import { MemoryStore } from './MemoryStore';
import { SkillStore } from './SkillStore';
import { SkillDoc } from '../core/SkillDoc';

const MAX_READ_BYTES: number = 1024 * 1024;
const MAX_IMAGE_BYTES: number = 5 * 1024 * 1024;
const MAX_RESULT_CHARS: number = 24000;
const MAX_SEARCH_FILES: number = 2000;
const MAX_SEARCH_BYTES: number = 512 * 1024;
const MAX_CLIPBOARD_CHARS: number = 100000;
const SKIP_DIRS: string[] = [
  '.git', '.hvigor', 'node_modules', 'oh_modules', 'build', 'dist', '.idea'
];
const BINARY_EXT: string[] = [
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', 'mp3', 'mp4', 'mov',
  'zip', 'gz', 'tar', '7z', 'so', 'hap', 'hsp', 'abc', 'class', 'jar', 'pdf'
];

interface ListDirArgs {
  path?: string;
}

interface ReadFileArgs {
  path?: string;
  offset?: number;
  limit?: number;
}

interface ReadImageArgs {
  path?: string;
}

interface WriteFileArgs {
  path?: string;
  content?: string;
}

interface EditFileArgs {
  path?: string;
  old_string?: string;
  new_string?: string;
  replace_all?: boolean;
}

interface SearchTextArgs {
  query?: string;
  path?: string;
  max_results?: number;
}

interface FetchUrlArgs {
  url?: string;
  method?: string;
  body?: string;
}

interface MemoryWriteArgs {
  content?: string;
}

interface MemoryGetArgs {
  query?: string;
  days?: number;
  limit?: number;
}

interface SubagentArgs {
  action?: string;
  prompt?: string;
  label?: string;
  job_id?: string;
  message?: string;
  wait?: boolean;
  max_minutes?: number;
}

interface ClipboardWriteArgs {
  text?: string;
}

interface ReadSkillArgs {
  id?: string;
}

interface GenerateImageArgs {
  prompt?: string;
  size?: string;
  model?: string;
}

function clamp(value: number, min: number, max: number): number {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}

function numberArg(value: number | undefined, fallback: number): number {
  if (value === undefined || Number.isNaN(value)) {
    return fallback;
  }
  return value;
}

function isBinaryName(name: string): boolean {
  const dot: number = name.lastIndexOf('.');
  if (dot < 0) {
    return false;
  }
  return BINARY_EXT.indexOf(name.substring(dot + 1).toLowerCase()) >= 0;
}

/** MIME type for the image formats the model can actually decode. */
function imageMimeFor(name: string): string {
  const dot: number = name.lastIndexOf('.');
  if (dot < 0) {
    return '';
  }
  const ext: string = name.substring(dot + 1).toLowerCase();
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

/**
 * Executes tools inside the application sandbox. Every path is resolved
 * against `workspaceRoot`; absolute paths, `..` and symlinks are rejected.
 */
export class LocalToolRuntime implements ToolRuntime {
  private root: string;
  private allowWrite: boolean;
  private memoryEnabled: boolean;
  private imagesEnabled: boolean;
  private subagent: SubagentHandler | null;
  private disabledTools: string[];
  private clipboardEnabled: boolean;
  private browser: BrowserHandler | null;
  private imageGen: ImageGenHandler | null;
  private device: DeviceToolsHandler | null;
  private imageCache: Map<string, string> = new Map();

  constructor(
    workspaceRoot: string,
    allowWrite: boolean,
    memoryEnabled: boolean,
    imagesEnabled: boolean,
    subagent: SubagentHandler | null = null,
    disabledTools: string[] = [],
    clipboardEnabled: boolean = false,
    browser: BrowserHandler | null = null,
    imageGen: ImageGenHandler | null = null,
    device: DeviceToolsHandler | null = null
  ) {
    this.root = workspaceRoot;
    this.allowWrite = allowWrite;
    this.memoryEnabled = memoryEnabled;
    this.imagesEnabled = imagesEnabled;
    this.subagent = subagent;
    this.disabledTools = disabledTools;
    this.clipboardEnabled = clipboardEnabled;
    this.browser = browser;
    this.imageGen = imageGen;
    this.device = device;
    try {
      if (!fs.accessSync(this.root)) {
        fs.mkdirSync(this.root, true);
      }
    } catch (e) {
      // The caller surfaces a tool error on first use.
    }
  }

  definitions(): ToolDefinition[] {
    const all: ToolDefinition[] = builtinToolDefinitions();
    // Never advertise a tool that would only answer "disabled".
    const available: ToolDefinition[] = [];
    for (let i = 0; i < all.length; i++) {
      const name: string = all[i].name;
      if (isToolDisabled(this.disabledTools, name)) {
        continue;
      }
      const writeTool: boolean = name === 'write_file' || name === 'file_edit';
      const memoryTool: boolean = name === 'memory_write' || name === 'memory_get';
      if (writeTool && !this.allowWrite) {
        continue;
      }
      if (memoryTool && !this.memoryEnabled) {
        continue;
      }
      if (name === 'read_image' && !this.imagesEnabled) {
        continue;
      }
      if ((name === 'clipboard_read' || name === 'clipboard_write') &&
        !this.clipboardEnabled) {
        continue;
      }
      if (name === 'read_skill' && SkillStore.list().length === 0) {
        continue;
      }
      if (name === 'subagent_task' && this.subagent === null) {
        continue;
      }
      if (name === 'browser_use' && this.browser === null) {
        continue;
      }
      if (name === 'generate_image' && this.imageGen === null) {
        continue;
      }
      if (name === 'calendar' || name === 'contacts' ||
        name === 'location' || name === 'weather') {
        if (this.device === null || !this.device.enabled(name)) {
          continue;
        }
      }
      available.push(all[i]);
    }
    return available;
  }

  async execute(name: string, argumentsJson: string): Promise<ToolResult> {
    try {
      if (isToolDisabled(this.disabledTools, name)) {
        return { ok: false, content: '工具已在此设备上关闭：' + name };
      }
      if (name === 'now') {
        const now: Date = new Date();
        return {
          ok: true,
          content: now.toString() + '\nepoch_ms=' + now.getTime().toString()
        };
      }
      if (name === 'list_dir') {
        return this.listDir(argumentsJson);
      }
      if (name === 'read_file') {
        return this.readFile(argumentsJson);
      }
      if (name === 'read_image') {
        return this.readImage(argumentsJson);
      }
      if (name === 'write_file') {
        return this.writeFile(argumentsJson);
      }
      if (name === 'file_edit') {
        return this.editFile(argumentsJson);
      }
      if (name === 'memory_write') {
        return this.memoryWrite(argumentsJson);
      }
      if (name === 'memory_get') {
        return this.memoryGet(argumentsJson);
      }
      if (name === 'read_skill') {
        return this.readSkill(argumentsJson);
      }
      if (name === 'clipboard_read') {
        return await this.clipboardRead();
      }
      if (name === 'clipboard_write') {
        return await this.clipboardWrite(argumentsJson);
      }
      if (name === 'search_text') {
        return this.searchText(argumentsJson);
      }
      if (name === 'fetch_url') {
        return await this.fetchUrl(argumentsJson);
      }
      if (name === 'subagent_task') {
        return await this.runSubagent(argumentsJson);
      }
      if (name === 'browser_use') {
        if (this.browser === null) {
          return { ok: false, content: '内置浏览器尚未就绪。' };
        }
        return await this.browser.execute(argumentsJson);
      }
      if (name === 'generate_image') {
        return await this.generateImage(argumentsJson);
      }
      if (name === 'calendar' || name === 'contacts' ||
        name === 'location' || name === 'weather') {
        if (this.device === null) {
          return { ok: false, content: '设备工具在此模式下不可用。' };
        }
        return await this.device.execute(name, argumentsJson);
      }
      return { ok: false, content: '未知工具：' + name };
    } catch (e) {
      const error: Error = e as Error;
      return { ok: false, content: '工具执行失败：' + error.message };
    }
  }

  imageDataUrl(uri: string, mimeType: string): string {
    if (!this.imagesEnabled) {
      return '';
    }
    try {
      const absolute: string = this.resolvePath(uri, false);
      const stat = fs.statSync(absolute);
      if (!stat.isFile() || stat.size <= 0 || stat.size > MAX_IMAGE_BYTES) {
        return '';
      }
      const mime: string = mimeType.length > 0 ? mimeType : imageMimeFor(absolute);
      if (mime.length === 0) {
        return '';
      }
      // The same image is re-requested on every tool round; encode it once.
      const key: string = uri + ':' + stat.size.toString() + ':' + stat.mtime.toString();
      const cached: string | undefined = this.imageCache.get(key);
      if (cached !== undefined) {
        return cached;
      }
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      const file = fs.openSync(absolute, fs.OpenMode.READ_ONLY);
      try {
        fs.readSync(file.fd, buffer);
      } finally {
        fs.closeSync(file);
      }
      const base64: string =
        new util.Base64Helper().encodeToStringSync(new Uint8Array(buffer));
      const dataUrl: string = 'data:' + mime + ';base64,' + base64;
      if (this.imageCache.size >= 8) {
        this.imageCache.clear();
      }
      this.imageCache.set(key, dataUrl);
      return dataUrl;
    } catch (e) {
      return '';
    }
  }

  private async generateImage(argumentsJson: string): Promise<ToolResult> {
    if (this.imageGen === null) {
      return {
        ok: false,
        content: '图像生成未开启。请在设置 → 工具与沙箱中允许图像生成，并使用 OpenAI 兼容协议。'
      };
    }
    const args: GenerateImageArgs = JSON.parse(argumentsJson) as GenerateImageArgs;
    const prompt: string = args.prompt !== undefined ? args.prompt.trim() : '';
    if (prompt.length === 0) {
      return { ok: false, content: 'prompt 不能为空。' };
    }
    if (prompt.length > 4000) {
      return { ok: false, content: 'prompt 太长（上限 4000 字符）。' };
    }
    const request: ImageGenRequest = {
      prompt: prompt,
      size: args.size !== undefined ? args.size : '',
      model: args.model !== undefined ? args.model : ''
    };
    return await this.imageGen.generate(request);
  }

  private async runSubagent(argumentsJson: string): Promise<ToolResult> {
    if (this.subagent === null) {
      return { ok: false, content: '当前模式不支持子代理。' };
    }
    const args: SubagentArgs = JSON.parse(argumentsJson) as SubagentArgs;
    const action: string = args.action !== undefined ? args.action.trim() : '';
    const prompt: string = args.prompt !== undefined ? args.prompt.trim() : '';
    if ((action.length === 0 || action === 'delegate') && prompt.length === 0) {
      return { ok: false, content: 'subagent_task 的 action=delegate 需要非空的 prompt。' };
    }
    const request: SubagentRequest = {
      action: action,
      prompt: prompt,
      label: args.label !== undefined ? args.label.trim() : '',
      jobId: args.job_id !== undefined ? args.job_id.trim() : '',
      message: args.message !== undefined ? args.message : '',
      wait: args.wait === true,
      maxMinutes: numberArg(args.max_minutes, 0)
    };
    return this.subagent.execute(request);
  }

  private resolvePath(raw: string, allowRoot: boolean): string {
    const relative: string | null = normalizeRelativePath(raw);
    if (relative === null) {
      throw new Error('路径必须是工作区内的相对路径，不能是绝对路径或包含 ..');
    }
    if (!allowRoot && relative.length === 0) {
      throw new Error('必须提供文件路径');
    }
    this.assertNoSymlink(relative);
    return resolveWorkspacePath(this.root, relative);
  }

  private assertNoSymlink(relative: string): void {
    if (relative.length === 0) {
      return;
    }
    const segments: string[] = relative.split('/');
    let current: string = this.root;
    for (let i = 0; i < segments.length; i++) {
      current += '/' + segments[i];
      try {
        if (fs.accessSync(current) && fs.lstatSync(current).isSymbolicLink()) {
          throw new Error('不允许访问符号链接：' + segments[i]);
        }
      } catch (e) {
        const error: Error = e as Error;
        if (error.message.indexOf('符号链接') >= 0) {
          throw error;
        }
        // Missing intermediate paths are fine; write_file creates them.
      }
    }
  }

  private listDir(argumentsJson: string): ToolResult {
    const args: ListDirArgs = JSON.parse(argumentsJson) as ListDirArgs;
    const raw: string = args.path !== undefined ? args.path : '';
    const absolute: string = this.resolvePath(raw, true);
    const names: string[] = fs.listFileSync(absolute);
    const lines: string[] = [];
    for (let i = 0; i < names.length && i < 500; i++) {
      const name: string = names[i];
      const child: string = absolute + '/' + name;
      let suffix: string = '';
      try {
        const stat = fs.statSync(child);
        if (stat.isDirectory()) {
          suffix = '/';
        } else {
          suffix = '  (' + stat.size.toString() + ' B)';
        }
      } catch (e) {
        suffix = '';
      }
      lines.push(name + suffix);
    }
    lines.sort();
    if (names.length > 500) {
      lines.push('…（共 ' + names.length.toString() + ' 项，已显示前 500 项）');
    }
    return {
      ok: true,
      content: lines.length > 0 ? lines.join('\n') : '（空目录）'
    };
  }

  private readFile(argumentsJson: string): ToolResult {
    const args: ReadFileArgs = JSON.parse(argumentsJson) as ReadFileArgs;
    const raw: string = args.path !== undefined ? args.path : '';
    const absolute: string = this.resolvePath(raw, false);
    const stat = fs.statSync(absolute);
    if (stat.isDirectory()) {
      return { ok: false, content: '这是一个目录，请使用 list_dir：' + raw };
    }
    if (isBinaryName(absolute)) {
      return { ok: false, content: '这是二进制文件，read_file 只读取文本：' + raw };
    }
    if (stat.size > MAX_READ_BYTES) {
      return {
        ok: false,
        content: '文件过大（' + stat.size.toString() + ' B），上限为 ' +
          MAX_READ_BYTES.toString() + ' B。请先用 search_text 定位。'
      };
    }
    const text: string = fs.readTextSync(absolute);
    const lines: string[] = text.split('\n');
    const offset: number = clamp(Math.floor(numberArg(args.offset, 0)), 0, lines.length);
    const limit: number = clamp(Math.floor(numberArg(args.limit, 400)), 1, 2000);
    const slice: string[] = lines.slice(offset, offset + limit);
    let content: string = slice.join('\n');
    const remaining: number = lines.length - offset - slice.length;
    if (remaining > 0) {
      content += '\n…（还有 ' + remaining.toString() + ' 行，可用 offset 继续读取）';
    }
    return { ok: true, content: truncateText(content, MAX_RESULT_CHARS) };
  }

  private readImage(argumentsJson: string): ToolResult {
    if (!this.imagesEnabled) {
      return {
        ok: false,
        content: '读取图片未开启。请在设置 → 工具与沙箱中允许读取图片，并确认当前模型支持视觉。'
      };
    }
    const args: ReadImageArgs = JSON.parse(argumentsJson) as ReadImageArgs;
    const raw: string = args.path !== undefined ? args.path : '';
    const relative: string | null = normalizeRelativePath(raw);
    if (relative === null || relative.length === 0) {
      return { ok: false, content: '路径必须是工作区内的相对文件路径。' };
    }
    const absolute: string = this.resolvePath(raw, false);
    const stat = fs.statSync(absolute);
    if (stat.isDirectory()) {
      return { ok: false, content: '这是一个目录，请提供图片文件路径：' + raw };
    }
    const mime: string = imageMimeFor(absolute);
    if (mime.length === 0) {
      return {
        ok: false,
        content: '不支持的图片格式（支持 png / jpg / jpeg / webp / gif / bmp）：' + raw
      };
    }
    if (stat.size <= 0) {
      return { ok: false, content: '图片文件为空：' + raw };
    }
    if (stat.size > MAX_IMAGE_BYTES) {
      return {
        ok: false,
        content: '图片过大（' + stat.size.toString() + ' B），上限为 ' +
          MAX_IMAGE_BYTES.toString() + ' B。请先压缩后再读取。'
      };
    }
    return {
      ok: true,
      content: 'Image loaded successfully.\nMIME: ' + mime +
        '\nBytes: ' + stat.size.toString(),
      imageUri: relative,
      imageMimeType: mime
    };
  }

  private writeFile(argumentsJson: string): ToolResult {
    if (!this.allowWrite) {
      return {
        ok: false,
        content: '写入工具未开启。请在设置 → 工具与沙箱中允许写入工作区文件。'
      };
    }
    const args: WriteFileArgs = JSON.parse(argumentsJson) as WriteFileArgs;
    const raw: string = args.path !== undefined ? args.path : '';
    const content: string = args.content !== undefined ? args.content : '';
    const absolute: string = this.resolvePath(raw, false);
    const slash: number = absolute.lastIndexOf('/');
    if (slash > 0) {
      const parent: string = absolute.substring(0, slash);
      if (!fs.accessSync(parent)) {
        fs.mkdirSync(parent, true);
      }
    }
    const file = fs.openSync(
      absolute,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
    );
    try {
      const written: number = fs.writeSync(file.fd, content);
      return {
        ok: true,
        content: '已写入 ' + written.toString() + ' 字符到 ' + raw
      };
    } finally {
      fs.closeSync(file);
    }
  }

  private editFile(argumentsJson: string): ToolResult {
    if (!this.allowWrite) {
      return {
        ok: false,
        content: '编辑工具未开启。请在设置 → 工具与沙箱中允许写入工作区文件。'
      };
    }
    const args: EditFileArgs = JSON.parse(argumentsJson) as EditFileArgs;
    const raw: string = args.path !== undefined ? args.path : '';
    const oldText: string = args.old_string !== undefined ? args.old_string : '';
    const newText: string = args.new_string !== undefined ? args.new_string : '';
    const replaceAll: boolean = args.replace_all === true;
    const absolute: string = this.resolvePath(raw, false);
    const stat = fs.statSync(absolute);
    if (stat.isDirectory()) {
      return { ok: false, content: '这是一个目录，不能编辑：' + raw };
    }
    if (isBinaryName(absolute)) {
      return { ok: false, content: '这是二进制文件，file_edit 只处理文本：' + raw };
    }
    if (stat.size > MAX_READ_BYTES) {
      return {
        ok: false,
        content: '文件过大（' + stat.size.toString() + ' B），上限为 ' +
          MAX_READ_BYTES.toString() + ' B。'
      };
    }
    const source: string = fs.readTextSync(absolute);
    const outcome: EditOutcome = applyExactEdit(source, oldText, newText, replaceAll);
    if (!outcome.ok) {
      return { ok: false, content: outcome.message };
    }
    const file = fs.openSync(
      absolute,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
    );
    try {
      fs.writeSync(file.fd, outcome.content);
    } finally {
      fs.closeSync(file);
    }
    return {
      ok: true,
      content: outcome.message + ' 文件：' + raw
    };
  }

  private searchText(argumentsJson: string): ToolResult {
    const args: SearchTextArgs = JSON.parse(argumentsJson) as SearchTextArgs;
    const query: string = args.query !== undefined ? args.query.trim() : '';
    if (query.length === 0) {
      return { ok: false, content: 'query 不能为空' };
    }
    const raw: string = args.path !== undefined ? args.path : '';
    const start: string = this.resolvePath(raw, true);
    const maxResults: number = clamp(
      Math.floor(numberArg(args.max_results, 40)), 1, 200
    );
    const needle: string = query.toLowerCase();
    const results: string[] = [];
    const stack: string[] = [start];
    let visited: number = 0;

    while (stack.length > 0 && results.length < maxResults && visited < MAX_SEARCH_FILES) {
      const dir: string = stack.pop() as string;
      let names: string[] = [];
      try {
        names = fs.listFileSync(dir);
      } catch (e) {
        continue;
      }
      for (let i = 0; i < names.length; i++) {
        const name: string = names[i];
        const child: string = dir + '/' + name;
        let isDirectory: boolean = false;
        let size: number = 0;
        try {
          const stat = fs.statSync(child);
          isDirectory = stat.isDirectory();
          size = stat.size;
        } catch (e) {
          continue;
        }
        if (isDirectory) {
          if (SKIP_DIRS.indexOf(name) < 0 && !name.startsWith('.')) {
            stack.push(child);
          }
          continue;
        }
        visited++;
        if (visited >= MAX_SEARCH_FILES || size > MAX_SEARCH_BYTES ||
          isBinaryName(name)) {
          continue;
        }
        let text: string = '';
        try {
          text = fs.readTextSync(child);
        } catch (e) {
          continue;
        }
        const lines: string[] = text.split('\n');
        const relative: string = child.substring(this.root.length + 1);
        for (let lineNo = 0; lineNo < lines.length; lineNo++) {
          if (lines[lineNo].toLowerCase().indexOf(needle) >= 0) {
            const snippet: string = lines[lineNo].length > 240
              ? lines[lineNo].substring(0, 240) + '…'
              : lines[lineNo];
            results.push(relative + ':' + (lineNo + 1).toString() + ': ' + snippet);
            if (results.length >= maxResults) {
              break;
            }
          }
        }
      }
    }

    let content: string = results.length > 0
      ? results.join('\n')
      : '没有找到包含“' + query + '”的文本';
    if (visited >= MAX_SEARCH_FILES) {
      content += '\n…（已扫描 ' + MAX_SEARCH_FILES.toString() + ' 个文件后停止）';
    }
    return { ok: true, content: truncateText(content, MAX_RESULT_CHARS) };
  }

  private memoryWrite(argumentsJson: string): ToolResult {
    if (!this.memoryEnabled) {
      return {
        ok: false,
        content: '持久记忆未开启。请在设置 → 工具与沙箱中打开。'
      };
    }
    const args: MemoryWriteArgs = JSON.parse(argumentsJson) as MemoryWriteArgs;
    const content: string = args.content !== undefined ? args.content : '';
    const status: string = MemoryStore.write(content);
    const ok: boolean = status.startsWith('已写入记忆');
    return { ok: ok, content: status };
  }

  private readSkill(argumentsJson: string): ToolResult {
    const args: ReadSkillArgs = JSON.parse(argumentsJson) as ReadSkillArgs;
    const id: string = args.id !== undefined ? args.id : '';
    const doc: SkillDoc | null = SkillStore.get(id);
    if (doc === null) {
      const names: string[] = [];
      const docs: SkillDoc[] = SkillStore.list();
      for (let i = 0; i < docs.length; i++) {
        names.push(docs[i].id);
      }
      return {
        ok: false,
        content: '没有找到技能：' + (id.length > 0 ? id : '（空）') +
          '。可用 id：' + (names.length > 0 ? names.join(', ') : '无')
      };
    }
    return { ok: true, content: doc.name + '\n\n' + doc.body };
  }

  private async clipboardRead(): Promise<ToolResult> {
    try {
      const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      const data: pasteboard.PasteData = await board.getData();
      let text: string = '';
      try {
        text = data.getPrimaryText();
      } catch (e) {
        text = '';
      }
      if (text.length === 0) {
        return { ok: true, content: '剪贴板中没有纯文本。' };
      }
      return { ok: true, content: truncateText(text, MAX_RESULT_CHARS) };
    } catch (e) {
      const error: Error = e as Error;
      return {
        ok: false,
        content: '读取剪贴板失败：' + error.message + '（系统可能要求用户在弹窗中允许粘贴）'
      };
    }
  }

  private async clipboardWrite(argumentsJson: string): Promise<ToolResult> {
    const args: ClipboardWriteArgs = JSON.parse(argumentsJson) as ClipboardWriteArgs;
    const text: string = args.text !== undefined ? args.text : '';
    if (text.length === 0) {
      return { ok: false, content: 'text 不能为空。' };
    }
    if (text.length > MAX_CLIPBOARD_CHARS) {
      return {
        ok: false,
        content: '文本过长（' + text.length.toString() + ' 字符），上限 ' +
          MAX_CLIPBOARD_CHARS.toString() + '。'
      };
    }
    try {
      const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      const data: pasteboard.PasteData = pasteboard.createData(
        pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await board.setData(data);
      return {
        ok: true,
        content: '已写入剪贴板（' + text.length.toString() + ' 字符）。'
      };
    } catch (e) {
      const error: Error = e as Error;
      return { ok: false, content: '写入剪贴板失败：' + error.message };
    }
  }

  private memoryGet(argumentsJson: string): ToolResult {
    if (!this.memoryEnabled) {
      return {
        ok: false,
        content: '持久记忆未开启。请在设置 → 工具与沙箱中打开。'
      };
    }
    const args: MemoryGetArgs = JSON.parse(argumentsJson) as MemoryGetArgs;
    const query: string = args.query !== undefined ? args.query : '';
    const days: number = clamp(Math.floor(numberArg(args.days, 7)), 1, 90);
    const limit: number = clamp(Math.floor(numberArg(args.limit, 20)), 1, 100);
    return {
      ok: true,
      content: MemoryStore.search(query, days, limit)
    };
  }

  private async fetchUrl(argumentsJson: string): Promise<ToolResult> {
    const args: FetchUrlArgs = JSON.parse(argumentsJson) as FetchUrlArgs;
    const url: string = args.url !== undefined ? args.url.trim() : '';
    if (!url.startsWith('https://') && !url.startsWith('http://')) {
      return { ok: false, content: '只支持 http:// 和 https:// 地址' };
    }
    const method: string = args.method !== undefined
      ? args.method.toUpperCase()
      : 'GET';
    const headers: Record<string, string> = {
      'Accept': 'text/plain, application/json, text/html;q=0.9, */*;q=0.5',
      'User-Agent': 'MinisHarmony/1.0 (HarmonyOS tablet)'
    };
    const options: http.HttpRequestOptions = {
      method: method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET,
      header: headers,
      connectTimeout: 15000,
      readTimeout: 30000,
      usingCache: false,
      expectDataType: http.HttpDataType.STRING
    };
    if (args.body !== undefined && args.body.length > 0) {
      options.extraData = args.body;
    }
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, options);
      const raw: string = response.result as string;
      if (response.responseCode >= 400) {
        return {
          ok: false,
          content: 'HTTP ' + response.responseCode.toString() + '\n' +
            truncateText(raw, 4000)
        };
      }
      return { ok: true, content: truncateText(raw, MAX_RESULT_CHARS) };
    } finally {
      request.destroy();
    }
  }
}
