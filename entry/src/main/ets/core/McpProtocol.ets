/**
 * Minimal MCP (Model Context Protocol) wire helpers.
 *
 * Transport is the "Streamable HTTP" flavour used by current servers: every
 * JSON-RPC message is POSTed to one endpoint, and the reply is either plain
 * JSON or an SSE stream of events. Only the JSON-RPC subset needed for tools
 * is implemented: `initialize`, `notifications/initialized`, `tools/list` and
 * `tools/call`.
 *
 * Everything here is pure so it can be unit-tested under Node.
 */

export const MCP_PROTOCOL_VERSION: string = '2024-11-05';

export interface McpServerConfig {
  id: string;
  name: string;
  url: string;
  /** JSON object of extra headers (for example an API token). */
  headers: string;
  enabled: boolean;
}

export interface McpRpcError {
  code?: number;
  message?: string;
}

export interface McpRpcResponse {
  jsonrpc?: string;
  id?: number;
  result?: Object;
  error?: McpRpcError;
}

export interface McpListedTool {
  name?: string;
  description?: string;
  inputSchema?: Object;
}

export interface McpToolsEnvelope {
  tools?: McpListedTool[];
}

export interface McpContentItem {
  type?: string;
  text?: string;
}

export interface McpCallEnvelope {
  content?: McpContentItem[];
  isError?: boolean;
}

export interface McpToolInfo {
  serverId: string;
  serverName: string;
  /** Tool name as the server knows it. */
  toolName: string;
  /** Name exposed to the model, unique across servers. */
  exposedName: string;
  description: string;
  /** Raw JSON Schema text; sent as the function parameters. */
  schemaJson: string;
}

export function defaultMcpServer(id: string): McpServerConfig {
  return { id: id, name: '', url: '', headers: '', enabled: true };
}

export function normalizeMcpServers(list: McpServerConfig[] | undefined): McpServerConfig[] {
  const out: McpServerConfig[] = [];
  if (list === undefined || !Array.isArray(list)) {
    return out;
  }
  for (let i = 0; i < list.length; i++) {
    const item: McpServerConfig = list[i];
    if (item === null || item === undefined) {
      continue;
    }
    const url: string = item.url !== undefined ? item.url.trim() : '';
    if (url.length === 0) {
      continue;
    }
    if (url.indexOf('http://') !== 0 && url.indexOf('https://') !== 0) {
      continue;
    }
    let duplicate: boolean = false;
    for (let j = 0; j < out.length; j++) {
      if (out[j].id === item.id) {
        duplicate = true;
        break;
      }
    }
    if (duplicate) {
      continue;
    }
    const name: string = item.name !== undefined && item.name.trim().length > 0
      ? item.name.trim()
      : url;
    out.push({
      id: item.id !== undefined && item.id.length > 0 ? item.id : url,
      name: name,
      url: url,
      headers: item.headers !== undefined ? item.headers : '',
      enabled: item.enabled !== false
    });
  }
  return out;
}

/** Sanitize a piece of a function name to `[A-Za-z0-9_-]`. */
function slug(text: string): string {
  let out: string = '';
  const lower: string = text.toLowerCase();
  for (let i = 0; i < lower.length; i++) {
    const code: number = lower.charCodeAt(i);
    const isLower: boolean = code >= 97 && code <= 122;
    const isDigit: boolean = code >= 48 && code <= 57;
    if (isLower || isDigit) {
      out += lower.charAt(i);
    } else if (code === 45 || code === 95) {
      out += lower.charAt(i);
    } else {
      out += '_';
    }
  }
  return out;
}

/**
 * Compose the name visible to the model. OpenAI function names are limited to
 * 64 characters and `[A-Za-z0-9_-]`, so both parts are sanitized and the tool
 * part is truncated when needed.
 */
export function exposedToolName(serverId: string, toolName: string): string {
  const httpServer: string = slug(serverId);
  const httpTool: string = slug(toolName);
  const serverPart: string = httpServer.length > 20 ? httpServer.substring(0, 20) : httpServer;
  const prefix: string = 'mcp_' + serverPart + '_';
  const room: number = 64 - prefix.length;
  const toolPart: string = httpTool.length > room ? httpTool.substring(0, room) : httpTool;
  return prefix + toolPart;
}

export function rpcRequest(id: number, method: string, paramsJson: string): string {
  return '{"jsonrpc":"2.0","id":' + id.toString() +
    ',"method":' + JSON.stringify(method) +
    ',"params":' + (paramsJson.length > 0 ? paramsJson : '{}') + '}';
}

export function rpcNotification(method: string, paramsJson: string): string {
  return '{"jsonrpc":"2.0","method":' + JSON.stringify(method) +
    ',"params":' + (paramsJson.length > 0 ? paramsJson : '{}') + '}';
}

export function initializeParams(): string {
  return '{"protocolVersion":"' + MCP_PROTOCOL_VERSION +
    '","capabilities":{},"clientInfo":{"name":"MinisHarmony","version":"1.0.0"}}';
}

/** Extract JSON payloads from an SSE body; returns the raw body when it is JSON. */
export function rpcPayloads(body: string): string[] {
  const trimmed: string = body.trim();
  const out: string[] = [];
  if (trimmed.length === 0) {
    return out;
  }
  if (trimmed.charAt(0) === '{' || trimmed.charAt(0) === '[') {
    out.push(trimmed);
    return out;
  }
  const lines: string[] = trimmed.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line: string = lines[i].trim();
    if (line.indexOf('data:') !== 0) {
      continue;
    }
    const payload: string = line.substring(5).trim();
    if (payload.length > 0 && payload !== '[DONE]') {
      out.push(payload);
    }
  }
  return out;
}

/**
 * Parse a response body (plain JSON or SSE) and return the JSON-RPC response
 * whose id matches, falling back to the first response-shaped payload.
 */
export function parseRpcBody(body: string, expectedId: number): McpRpcResponse | null {
  const payloads: string[] = rpcPayloads(body);
  let fallback: McpRpcResponse | null = null;
  for (let i = 0; i < payloads.length; i++) {
    let parsed: McpRpcResponse;
    try {
      parsed = JSON.parse(payloads[i]) as McpRpcResponse;
    } catch (e) {
      continue;
    }
    if (parsed === null || typeof parsed !== 'object') {
      continue;
    }
    if (parsed.id !== undefined && parsed.id === expectedId) {
      return parsed;
    }
    if (fallback === null &&
      (parsed.result !== undefined || parsed.error !== undefined)) {
      fallback = parsed;
    }
  }
  return fallback;
}

export function rpcErrorMessage(response: McpRpcResponse): string {
  if (response.error === undefined || response.error === null) {
    return '';
  }
  const code: string = response.error.code !== undefined
    ? ' (' + response.error.code.toString() + ')'
    : '';
  const message: string = response.error.message !== undefined
    ? response.error.message
    : '未知错误';
  return 'MCP 错误' + code + '：' + message;
}

export function toolsFromResult(
  serverId: string,
  serverName: string,
  resultJson: string
): McpToolInfo[] {
  const out: McpToolInfo[] = [];
  let envelope: McpToolsEnvelope;
  try {
    envelope = JSON.parse(resultJson) as McpToolsEnvelope;
  } catch (e) {
    return out;
  }
  if (envelope === null || envelope.tools === undefined || !Array.isArray(envelope.tools)) {
    return out;
  }
  for (let i = 0; i < envelope.tools.length; i++) {
    const tool: McpListedTool = envelope.tools[i];
    if (tool === null || tool === undefined) {
      continue;
    }
    const name: string = tool.name !== undefined ? tool.name.trim() : '';
    if (name.length === 0) {
      continue;
    }
    let schema: string = '{"type":"object","properties":{},"required":[]}';
    if (tool.inputSchema !== undefined && tool.inputSchema !== null) {
      try {
        schema = JSON.stringify(tool.inputSchema);
      } catch (e) {
        schema = '{"type":"object","properties":{},"required":[]}';
      }
    }
    out.push({
      serverId: serverId,
      serverName: serverName,
      toolName: name,
      exposedName: exposedToolName(serverId, name),
      description: tool.description !== undefined ? tool.description : '',
      schemaJson: schema
    });
  }
  return out;
}

/**
 * Flatten a `tools/call` result into plain text. Text items are concatenated;
 * images/audio/resources are represented by a short placeholder so the model
 * still knows they were returned.
 */
export function callResultText(resultJson: string): string {
  let envelope: McpCallEnvelope;
  try {
    envelope = JSON.parse(resultJson) as McpCallEnvelope;
  } catch (e) {
    return '';
  }
  if (envelope === null || envelope.content === undefined ||
    !Array.isArray(envelope.content)) {
    return '';
  }
  const parts: string[] = [];
  for (let i = 0; i < envelope.content.length; i++) {
    const item: McpContentItem = envelope.content[i];
    if (item === null || item === undefined) {
      continue;
    }
    if (item.text !== undefined && item.text.length > 0) {
      parts.push(item.text);
      continue;
    }
    if (item.type !== undefined && item.type.length > 0) {
      parts.push('[' + item.type + ' 内容未展开]');
    }
  }
  return parts.join('\n');
}

export function isCallError(resultJson: string): boolean {
  let envelope: McpCallEnvelope;
  try {
    envelope = JSON.parse(resultJson) as McpCallEnvelope;
  } catch (e) {
    return false;
  }
  return envelope !== null && envelope.isError === true;
}
