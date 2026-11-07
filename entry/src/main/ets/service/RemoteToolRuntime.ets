import { http } from '@kit.NetworkKit';
import { ToolDefinition, ToolResult, ToolRuntime } from '../core/ToolTypes';
import { builtinToolDefinitions } from '../core/ToolCatalog';
import { truncateText } from '../core/Workspace';

interface RemoteToolRequest {
  name: string;
  arguments: string;
}

interface RemoteToolResponse {
  ok?: boolean;
  content?: string;
  error?: string;
}

/**
 * Forwards the same tool surface to a helper process on a PC/NAS/VPS. The
 * helper contract is deliberately small:
 *
 *   POST <endpoint>
 *   Authorization: Bearer <token>            (optional)
 *   { "name": "read_file", "arguments": "{\"path\":\"a.txt\"}" }
 *   -> { "ok": true, "content": "..." }
 *
 * It lets the tablet use a real shell/workspace while the UI and agent loop
 * stay on-device. The QEMU backend will implement the same interface.
 */
export class RemoteToolRuntime implements ToolRuntime {
  private endpoint: string;
  private token: string;
  private allowWrite: boolean;

  constructor(endpoint: string, token: string, allowWrite: boolean) {
    this.endpoint = endpoint.trim();
    this.token = token.trim();
    this.allowWrite = allowWrite;
  }

  definitions(): ToolDefinition[] {
    const all: ToolDefinition[] = builtinToolDefinitions();
    if (this.allowWrite) {
      return all;
    }
    // Keep the remote workspace read-only unless the user opted in.
    const readonly: ToolDefinition[] = [];
    for (let i = 0; i < all.length; i++) {
      if (all[i].name !== 'write_file') {
        readonly.push(all[i]);
      }
    }
    return readonly;
  }

  async execute(name: string, argumentsJson: string): Promise<ToolResult> {
    if (name === 'write_file' && !this.allowWrite) {
      return {
        ok: false,
        content: '写入工具未开启。请在设置 → 工具与沙箱中允许写入。'
      };
    }
    if (this.endpoint.length === 0) {
      return { ok: false, content: '远程沙箱地址未配置，请在设置 → 工具与沙箱中填写。' };
    }
    if (!this.endpoint.startsWith('https://') &&
      !this.endpoint.startsWith('http://')) {
      return { ok: false, content: '远程沙箱地址必须以 http:// 或 https:// 开头。' };
    }
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'MinisHarmony/1.0 (HarmonyOS tablet)'
    };
    if (this.token.length > 0) {
      headers['Authorization'] = 'Bearer ' + this.token;
    }
    const body: RemoteToolRequest = {
      name: name,
      arguments: argumentsJson
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: JSON.stringify(body),
      connectTimeout: 15000,
      readTimeout: 120000,
      usingCache: false,
      expectDataType: http.HttpDataType.STRING
    };
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(this.endpoint, options);
      const raw: string = response.result as string;
      if (response.responseCode >= 400) {
        return {
          ok: false,
          content: '远程沙箱 HTTP ' + response.responseCode.toString() + '\n' +
            truncateText(raw, 2000)
        };
      }
      let parsed: RemoteToolResponse;
      try {
        parsed = JSON.parse(raw) as RemoteToolResponse;
      } catch (e) {
        return {
          ok: false,
          content: '远程沙箱返回了非 JSON 内容：\n' + truncateText(raw, 2000)
        };
      }
      const content: string = parsed.content !== undefined
        ? parsed.content
        : (parsed.error !== undefined ? parsed.error : '');
      return {
        ok: parsed.ok === true,
        content: truncateText(content, 24000)
      };
    } catch (e) {
      const error: Error = e as Error;
      return { ok: false, content: '远程沙箱连接失败：' + error.message };
    } finally {
      request.destroy();
    }
  }
}
