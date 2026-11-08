import { ToolDefinition, ToolParameters, ToolResult, ToolProperty, ToolRuntime } from '../core/ToolTypes';
import { McpServerConfig, McpToolInfo } from '../core/McpProtocol';
import { McpClient } from './McpClient';
import { McpOAuthService } from './McpOAuth';

export interface McpServerStatus {
  serverId: string;
  serverName: string;
  toolCount: number;
  error: string;
}

function emptyParameters(): ToolParameters {
  const properties: Record<string, ToolProperty> = {};
  return { type: 'object', properties: properties, required: [] };
}

function definitionFor(info: McpToolInfo): ToolDefinition {
  return {
    name: info.exposedName,
    description: info.description.length > 0
      ? info.description
      : 'MCP 工具 ' + info.toolName + '（来自 ' + info.serverName + '）',
    parameters: emptyParameters(),
    schemaJson: info.schemaJson
  };
}

/**
 * Process-wide cache of discovered MCP tools.
 *
 * Discovery is async and never blocks a send: the app refreshes at launch,
 * when settings are saved, and on the manual refresh button. `runAgent`
 * reads whatever has been discovered so far, so a slow or offline server
 * simply contributes no tools for that turn.
 */
class McpRegistryStore {
  private tools: McpToolInfo[] = [];
  private clients: Map<string, McpClient> = new Map();
  private statuses: McpServerStatus[] = [];
  private signature: string = '';
  private seq: number = 0;

  currentStatuses(): McpServerStatus[] {
    return this.statuses;
  }

  toolCount(): number {
    return this.tools.length;
  }

  /** Re-discover every enabled server; servers are queried in parallel. */
  async refresh(servers: McpServerConfig[], force: boolean = false): Promise<McpServerStatus[]> {
    const enabled: McpServerConfig[] = [];
    for (let i = 0; i < servers.length; i++) {
      if (servers[i].enabled) {
        enabled.push(servers[i]);
      }
    }
    const signature: string = JSON.stringify(enabled);
    if (!force && signature === this.signature && this.statuses.length > 0) {
      return this.statuses;
    }
    this.seq++;
    const seq: number = this.seq;
    // Resolve OAuth tokens first (refreshing in parallel), then discover.
    const tokenTasks: Promise<string>[] = [];
    for (let i = 0; i < enabled.length; i++) {
      tokenTasks.push(McpOAuthService.validToken(enabled[i]));
    }
    const bearers: string[] = await Promise.all(tokenTasks);
    const clients: McpClient[] = [];
    const tasks: Promise<McpToolInfo[]>[] = [];
    for (let i = 0; i < enabled.length; i++) {
      const client: McpClient = new McpClient(enabled[i], bearers[i]);
      clients.push(client);
      tasks.push(client.listTools());
    }
    const results: McpToolInfo[][] = await Promise.all(tasks);
    if (seq !== this.seq) {
      return this.statuses;
    }
    const tools: McpToolInfo[] = [];
    const statuses: McpServerStatus[] = [];
    const nextClients: Map<string, McpClient> = new Map();
    for (let i = 0; i < clients.length; i++) {
      const client: McpClient = clients[i];
      statuses.push({
        serverId: client.config.id,
        serverName: client.config.name,
        toolCount: results[i].length,
        error: client.lastError
      });
      if (results[i].length > 0) {
        nextClients.set(client.config.id, client);
      }
      for (let j = 0; j < results[i].length; j++) {
        tools.push(results[i][j]);
      }
    }
    this.tools = tools;
    this.clients = nextClients;
    this.statuses = statuses;
    this.signature = signature;
    return statuses;
  }

  definitions(disabledTools: string[]): ToolDefinition[] {
    const out: ToolDefinition[] = [];
    for (let i = 0; i < this.tools.length; i++) {
      const name: string = this.tools[i].exposedName;
      if (disabledTools.indexOf(name) >= 0) {
        continue;
      }
      out.push(definitionFor(this.tools[i]));
    }
    return out;
  }

  /** Returns null when the name is not an MCP tool. */
  async call(exposedName: string, argumentsJson: string): Promise<ToolResult | null> {
    for (let i = 0; i < this.tools.length; i++) {
      const info: McpToolInfo = this.tools[i];
      if (info.exposedName !== exposedName) {
        continue;
      }
      const client: McpClient | undefined = this.clients.get(info.serverId);
      if (client === undefined) {
        return { ok: false, content: 'MCP 服务未连接：' + info.serverName };
      }
      return client.callTool(info.toolName, argumentsJson);
    }
    return null;
  }
}

export const McpRegistry: McpRegistryStore = new McpRegistryStore();

/**
 * Adds MCP tools on top of the local/remote sandbox runtime. Built-in tools
 * keep their behaviour; MCP names never collide because of the `mcp_` prefix.
 */
export class McpRuntime implements ToolRuntime {
  private inner: ToolRuntime;
  private disabledTools: string[];

  constructor(inner: ToolRuntime, disabledTools: string[]) {
    this.inner = inner;
    this.disabledTools = disabledTools;
  }

  definitions(): ToolDefinition[] {
    const base: ToolDefinition[] = this.inner.definitions();
    const extra: ToolDefinition[] = McpRegistry.definitions(this.disabledTools);
    for (let i = 0; i < extra.length; i++) {
      base.push(extra[i]);
    }
    return base;
  }

  async execute(name: string, argumentsJson: string): Promise<ToolResult> {
    const mcpResult: ToolResult | null = await McpRegistry.call(name, argumentsJson);
    if (mcpResult !== null) {
      return mcpResult;
    }
    return this.inner.execute(name, argumentsJson);
  }

  imageDataUrl(uri: string, mimeType: string): string {
    return this.inner.imageDataUrl(uri, mimeType);
  }
}
