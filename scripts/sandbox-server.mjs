#!/usr/bin/env node
/**
 * Reference remote tool service for Minis Harmony.
 *
 * It implements the same six tools as LocalToolRuntime and the contract the
 * app's RemoteToolRuntime expects:
 *
 *   POST /tool
 *   Authorization: Bearer <token>          (when --token / SANDBOX_TOKEN is set)
 *   { "name": "read_file", "arguments": "{\"path\":\"a.txt\"}" }
 *   -> { "ok": true, "content": "..." }
 *
 * Everything is confined to --root. No shell, no exec, no path escapes.
 *
 *   node scripts/sandbox-server.mjs --root ~/minis-workspace --port 8787
 *   node scripts/sandbox-server.mjs --root ~/ws --host 0.0.0.0 --token SECRET
 *
 * Binding 0.0.0.0 exposes the service to your network. Only do that with a
 * token and a firewall; prefer Tailscale / an SSH tunnel for remote use.
 */
import { createServer } from 'node:http';
import { promises as fs } from 'node:fs';
import path from 'node:path';

const MAX_BODY = 1024 * 1024;
const MAX_READ = 1024 * 1024;
const MAX_RESULT = 24000;
const MAX_SEARCH_FILES = 2000;
const MAX_SEARCH_BYTES = 512 * 1024;
const SKIP_DIRS = new Set([
  '.git', '.hvigor', 'node_modules', 'oh_modules', 'build', 'dist', '.idea'
]);
const BINARY_EXT = new Set([
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', 'mp3', 'mp4', 'mov',
  'zip', 'gz', 'tar', '7z', 'so', 'hap', 'hsp', 'abc', 'class', 'jar', 'pdf'
]);

function fail(message) {
  return { ok: false, content: message };
}

function truncate(text, max = MAX_RESULT) {
  if (text.length <= max) {
    return text;
  }
  return text.substring(0, max) + `\n…（已截断，共 ${text.length} 字符）`;
}

function parseArgs(argv) {
  const options = {
    root: '',
    host: '127.0.0.1',
    port: 8787,
    token: process.env.SANDBOX_TOKEN ?? ''
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const next = () => {
      const value = argv[++i];
      if (value === undefined) {
        throw new Error(`${arg} 缺少值`);
      }
      return value;
    };
    if (arg === '--root') {
      options.root = next();
    } else if (arg === '--host') {
      options.host = next();
    } else if (arg === '--port') {
      options.port = Number(next());
    } else if (arg === '--token') {
      options.token = next();
    } else if (arg === '--help' || arg === '-h') {
      console.log('用法: node scripts/sandbox-server.mjs --root <dir> [--host 127.0.0.1] [--port 8787] [--token SECRET]');
      process.exit(0);
    } else {
      throw new Error(`未知参数: ${arg}`);
    }
  }
  if (!options.root) {
    throw new Error('必须用 --root 指定工作区目录');
  }
  if (!Number.isInteger(options.port) || options.port <= 0 || options.port > 65535) {
    throw new Error('端口无效');
  }
  return options;
}

function isBinaryName(name) {
  const dot = name.lastIndexOf('.');
  if (dot < 0) {
    return false;
  }
  return BINARY_EXT.has(name.substring(dot + 1).toLowerCase());
}

function normalizeRelative(raw) {
  let value = String(raw ?? '').trim();
  if (value.length === 0) {
    return '';
  }
  value = value.split('\\').join('/');
  if (value.startsWith('/')) {
    throw new Error('路径必须是工作区内的相对路径');
  }
  const segments = value.split('/');
  const out = [];
  for (const segment of segments) {
    if (segment.length === 0 || segment === '.') {
      continue;
    }
    if (segment === '..') {
      throw new Error('路径不能包含 ..');
    }
    out.push(segment);
  }
  return out.join('/');
}

async function resolveInside(root, raw, allowRoot) {
  const relative = normalizeRelative(raw);
  if (!allowRoot && relative.length === 0) {
    throw new Error('必须提供文件路径');
  }
  const absolute = relative.length === 0 ? root : path.join(root, relative);
  if (absolute !== root && !absolute.startsWith(root + path.sep)) {
    throw new Error('路径越界');
  }
  // Reject symlinks in every existing segment, including the target itself.
  const segments = relative.length === 0 ? [] : relative.split('/');
  let current = root;
  for (const segment of segments) {
    current = path.join(current, segment);
    try {
      const stat = await fs.lstat(current);
      if (stat.isSymbolicLink()) {
        throw new Error(`不允许访问符号链接：${segment}`);
      }
    } catch (error) {
      if (error.code === 'ENOENT') {
        break;
      }
      throw error;
    }
  }
  return { relative, absolute };
}

async function listDir(root, args) {
  const { absolute } = await resolveInside(root, args.path, true);
  const names = await fs.readdir(absolute, { withFileTypes: true });
  const lines = [];
  for (const entry of names.slice(0, 500)) {
    if (entry.isSymbolicLink()) {
      continue;
    }
    if (entry.isDirectory()) {
      lines.push(entry.name + '/');
      continue;
    }
    let suffix = '';
    try {
      const stat = await fs.stat(path.join(absolute, entry.name));
      suffix = `  (${stat.size} B)`;
    } catch {
      suffix = '';
    }
    lines.push(entry.name + suffix);
  }
  lines.sort();
  if (names.length > 500) {
    lines.push(`…（共 ${names.length} 项，已显示前 500 项）`);
  }
  return { ok: true, content: lines.length > 0 ? lines.join('\n') : '（空目录）' };
}

async function readFile(root, args) {
  const { relative, absolute } = await resolveInside(root, args.path, false);
  const stat = await fs.stat(absolute);
  if (stat.isDirectory()) {
    return fail(`这是一个目录，请使用 list_dir：${relative}`);
  }
  if (isBinaryName(absolute)) {
    return fail(`这是二进制文件，read_file 只读取文本：${relative}`);
  }
  if (stat.size > MAX_READ) {
    return fail(`文件过大（${stat.size} B），上限为 ${MAX_READ} B。请先用 search_text 定位。`);
  }
  const text = await fs.readFile(absolute, 'utf8');
  const lines = text.split('\n');
  const offset = Math.max(0, Math.min(lines.length, Math.floor(Number(args.offset ?? 0)) || 0));
  const limit = Math.max(1, Math.min(2000, Math.floor(Number(args.limit ?? 400)) || 400));
  const slice = lines.slice(offset, offset + limit);
  let content = slice.join('\n');
  const remaining = lines.length - offset - slice.length;
  if (remaining > 0) {
    content += `\n…（还有 ${remaining} 行，可用 offset 继续读取）`;
  }
  return { ok: true, content: truncate(content) };
}

async function writeFile(root, args) {
  const { relative, absolute } = await resolveInside(root, args.path, false);
  const parent = path.dirname(absolute);
  if (parent !== root && !parent.startsWith(root + path.sep)) {
    return fail('路径越界');
  }
  await fs.mkdir(parent, { recursive: true });
  const content = String(args.content ?? '');
  await fs.writeFile(absolute, content, 'utf8');
  return { ok: true, content: `已写入 ${content.length} 字符到 ${relative}` };
}

async function searchText(root, args) {
  const query = String(args.query ?? '').trim();
  if (query.length === 0) {
    return fail('query 不能为空');
  }
  const { absolute: start } = await resolveInside(root, args.path, true);
  const maxResults = Math.max(1, Math.min(200, Math.floor(Number(args.max_results ?? 40)) || 40));
  const needle = query.toLowerCase();
  const results = [];
  const stack = [start];
  let visited = 0;

  while (stack.length > 0 && results.length < maxResults && visited < MAX_SEARCH_FILES) {
    const dir = stack.pop();
    let names = [];
    try {
      names = await fs.readdir(dir);
    } catch {
      continue;
    }
    for (const name of names) {
      const child = path.join(dir, name);
      let stat;
      try {
        // lstat: never follow a symlink out of the workspace.
        stat = await fs.lstat(child);
      } catch {
        continue;
      }
      if (stat.isSymbolicLink()) {
        continue;
      }
      if (stat.isDirectory()) {
        if (!SKIP_DIRS.has(name) && !name.startsWith('.')) {
          stack.push(child);
        }
        continue;
      }
      visited++;
      if (visited >= MAX_SEARCH_FILES || stat.size > MAX_SEARCH_BYTES || isBinaryName(name)) {
        continue;
      }
      let text = '';
      try {
        text = await fs.readFile(child, 'utf8');
      } catch {
        continue;
      }
      const lines = text.split('\n');
      const relative = child.substring(root.length + 1);
      for (let lineNo = 0; lineNo < lines.length; lineNo++) {
        if (lines[lineNo].toLowerCase().includes(needle)) {
          const snippet = lines[lineNo].length > 240
            ? lines[lineNo].substring(0, 240) + '…'
            : lines[lineNo];
          results.push(`${relative}:${lineNo + 1}: ${snippet}`);
          if (results.length >= maxResults) {
            break;
          }
        }
      }
    }
  }

  let content = results.length > 0
    ? results.join('\n')
    : `没有找到包含“${query}”的文本`;
  if (visited >= MAX_SEARCH_FILES) {
    content += `\n…（已扫描 ${MAX_SEARCH_FILES} 个文件后停止）`;
  }
  return { ok: true, content: truncate(content) };
}

async function fetchUrl(args) {
  const url = String(args.url ?? '').trim();
  if (!url.startsWith('https://') && !url.startsWith('http://')) {
    return fail('只支持 http:// 和 https:// 地址');
  }
  const method = String(args.method ?? 'GET').toUpperCase() === 'POST' ? 'POST' : 'GET';
  const response = await fetch(url, {
    method,
    body: method === 'POST' && args.body ? String(args.body) : undefined,
    headers: {
      Accept: 'text/plain, application/json, text/html;q=0.9, */*;q=0.5',
      'User-Agent': 'MinisHarmony-Sandbox/1.0'
    },
    signal: AbortSignal.timeout(30000)
  });
  const raw = await response.text();
  if (!response.ok) {
    return fail(`HTTP ${response.status}\n${truncate(raw, 4000)}`);
  }
  return { ok: true, content: truncate(raw) };
}

async function execute(root, name, args) {
  if (name === 'list_dir') {
    return listDir(root, args);
  }
  if (name === 'read_file') {
    return readFile(root, args);
  }
  if (name === 'write_file') {
    return writeFile(root, args);
  }
  if (name === 'search_text') {
    return searchText(root, args);
  }
  if (name === 'fetch_url') {
    return fetchUrl(args);
  }
  if (name === 'now') {
    const now = new Date();
    return { ok: true, content: `${now.toString()}\nepoch_ms=${now.getTime()}` };
  }
  return fail(`未知工具：${name}`);
}

function readBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    request.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY) {
        reject(new Error('请求体过大'));
        request.destroy();
        return;
      }
      chunks.push(chunk);
    });
    request.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    request.on('error', reject);
  });
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const root = await fs.realpath(options.root);
  const stat = await fs.stat(root);
  if (!stat.isDirectory()) {
    throw new Error(`--root 不是目录: ${root}`);
  }

  const server = createServer(async (request, response) => {
    const send = (code, body) => {
      const payload = JSON.stringify(body);
      response.writeHead(code, {
        'Content-Type': 'application/json; charset=utf-8',
        'Content-Length': Buffer.byteLength(payload)
      });
      response.end(payload);
    };

    if (request.method !== 'POST') {
      send(405, fail('只接受 POST'));
      return;
    }
    if (options.token) {
      const auth = request.headers.authorization ?? '';
      if (auth !== `Bearer ${options.token}`) {
        send(401, fail('Token 无效'));
        return;
      }
    }

    let payload;
    try {
      payload = JSON.parse(await readBody(request));
    } catch (error) {
      send(400, fail(`请求体不是合法 JSON：${error.message}`));
      return;
    }
    const name = typeof payload.name === 'string' ? payload.name : '';
    if (!name) {
      send(400, fail('缺少 name'));
      return;
    }
    let args = {};
    if (typeof payload.arguments === 'string' && payload.arguments.trim().length > 0) {
      try {
        args = JSON.parse(payload.arguments);
      } catch (error) {
        send(400, fail(`arguments 不是合法 JSON：${error.message}`));
        return;
      }
    } else if (payload.arguments && typeof payload.arguments === 'object') {
      args = payload.arguments;
    }

    const started = Date.now();
    try {
      const result = await execute(root, name, args);
      console.log(`${new Date().toISOString()} ${name} ${result.ok ? 'ok' : 'error'} ${Date.now() - started}ms`);
      send(200, result);
    } catch (error) {
      console.log(`${new Date().toISOString()} ${name} error ${error.message}`);
      send(200, fail(`工具执行失败：${error.message}`));
    }
  });

  server.listen(options.port, options.host, () => {
    console.log(`Minis sandbox listening on http://${options.host}:${options.port}/tool`);
    console.log(`root: ${root}`);
    console.log(options.token ? 'auth: Bearer token required' : 'auth: disabled (local use only)');
  });
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
