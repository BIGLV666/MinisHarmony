import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ToolResult } from '../core/ToolTypes';
import { parseExtraHeaders } from '../core/ModelOverride';
import {
  McpRpcResponse,
  McpServerConfig,
  McpToolInfo,
  MCP_PROTOCOL_VERSION,
  callResultText,
  initializeParams,
  isCallError,
  parseRpcBody,
  rpcErrorMessage,
  rpcNotification,
  rpcRequest,
  toolsFromResult
} from '../core/McpProtocol';

function headersOf(config: McpServerConfig, sessionId: string): Record<string, string> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'Accept': 'application/json, text/event-stream',
    'Mcp-Protocol-Version': MCP_PROTOCOL_VERSION
  };
  const extra: Record<string, string> | null = parseExtraHeaders(config.headers);
  if (extra !== null) {
    const keys: string[] = Object.keys(extra);
    for (let i = 0; i < keys.length; i++) {
      headers[keys[i]] = extra[keys[i]];
    }
  }
  if (sessionId.length > 0) {
    headers['Mcp-Session-Id'] = sessionId;
  }
  return headers;
}

/**
 * One MCP server over Streamable HTTP. Tools are discovered on `listTools()`
 * and executed by `callTool()`; both are best-effort and report failures as
 * tool results rather than throwing into the agent loop.
 */
export class McpClient {
  config: McpServerConfig;
  private nextId: number = 1;
  private sessionId: string = '';
  private tools: McpToolInfo[] = [];
  lastError: string = '';

  constructor(config: McpServerConfig) {
    this.config = config;
  }

  private async post(payload: string, expectReply: boolean): Promise<McpRpcResponse | null> {
    const request: http.HttpRequest = http.createHttp();
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headersOf(this.config, this.sessionId),
      extraData: payload,
      connectTimeout: 15000,
      readTimeout: 60000,
      usingCache: false,
      expectDataType: http.HttpDataType.STRING
    };
    try {
      const response: http.HttpResponse = await request.request(this.config.url, options);
      const raw: string = typeof response.result === 'string'
        ? response.result as string
        : '';
      if (response.responseCode < 200 || response.responseCode >= 300) {
        this.lastError = 'HTTP ' + response.responseCode.toString() +
          (raw.length > 0 ? '：' + raw.substring(0, 200) : '');
        return null;
      }
      if (this.sessionId.length === 0) {
        const headers: Record<string, string> =
          response.header as Record<string, string>;
        const session: string | undefined = headers !== undefined
          ? headers['mcp-session-id']
          : undefined;
        if (session !== undefined && session.length > 0) {
          this.sessionId = session;
        }
      }
      if (!expectReply) {
        return null;
      }
      const parsed: McpRpcResponse | null = parseRpcBody(raw, this.nextId - 1);
      if (parsed === null) {
        this.lastError = '响应不是有效的 JSON-RPC：' + raw.substring(0, 200);
      }
      return parsed;
    } catch (e) {
      const error: BusinessError = e as BusinessError;
      this.lastError = error.message !== undefined ? error.message : '网络错误';
      return null;
    } finally {
      request.destroy();
    }
  }

  /** Initialize the session and fetch `tools/list`; returns [] on failure. */
  async listTools(): Promise<McpToolInfo[]> {
    this.lastError = '';
    this.sessionId = '';
    this.nextId = 1;
    const initId: number = this.nextId++;
    const init: McpRpcResponse | null = await this.post(
      rpcRequest(initId, 'initialize', initializeParams()), true);
    if (init === null || init.error !== undefined) {
      if (init !== null) {
        this.lastError = rpcErrorMessage(init);
      }
      this.tools = [];
      return this.tools;
    }
    await this.post(rpcNotification('notifications/initialized', ''), false);
    const listId: number = this.nextId++;
    const listed: McpRpcResponse | null = await this.post(
      rpcRequest(listId, 'tools/list', ''), true);
    if (listed === null || listed.error !== undefined || listed.result === undefined) {
      if (listed !== null && listed.error !== undefined) {
        this.lastError = rpcErrorMessage(listed);
      }
      this.tools = [];
      return this.tools;
    }
    this.tools = toolsFromResult(
      this.config.id, this.config.name, JSON.stringify(listed.result));
    return this.tools;
  }

  async callTool(toolName: string, argumentsJson: string): Promise<ToolResult> {
    let args: Object;
    try {
      args = JSON.parse(argumentsJson.length > 0 ? argumentsJson : '{}') as Object;
    } catch (e) {
      return { ok: false, content: '工具参数不是合法 JSON：' + toolName };
    }
    const params: string = JSON.stringify({ name: toolName, arguments: args });
    const id: number = this.nextId++;
    const response: McpRpcResponse | null = await this.post(
      rpcRequest(id, 'tools/call', params), true);
    if (response === null) {
      return {
        ok: false,
        content: 'MCP 服务「' + this.config.name + '」无响应：' + this.lastError
      };
    }
    if (response.error !== undefined || response.result === undefined) {
      return {
        ok: false,
        content: 'MCP 服务「' + this.config.name + '」调用失败：' + rpcErrorMessage(response)
      };
    }
    const resultJson: string = JSON.stringify(response.result);
    const text: string = callResultText(resultJson);
    const failed: boolean = isCallError(resultJson);
    return {
      ok: !failed,
      content: text.length > 0
        ? text
        : (failed ? 'MCP 工具返回错误，但没有文本内容' : 'MCP 工具执行完成，无文本输出')
    };
  }
}
