import { ToolDefinition, ToolParameters, ToolResult, ToolProperty, ToolRuntime } from '../core/ToolTypes';
import { McpServerConfig, McpToolInfo } from '../core/McpProtocol';
import { McpClient } from './McpClient';
import { McpOAuthService } from './McpOAuth';
import { t } from '../core/I18n';

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
      : t('MCP 工具 ') + info.toolName + t('（来自 ') + info.serverName + t('）'),
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
  /** Servers whose global switch is off but whose tools are cached anyway. */
  private globallyDisabled: string[] = [];

  currentStatuses(): McpServerStatus[] {
    return this.statuses;
  }

  toolCount(): number {
    return this.tools.length;
  }

  /**
   * Re-discover servers in parallel. `includeDisabled` additionally connects
   * globally disabled servers so a session can force one back on; their tools
   * are cached but hidden unless the session lists them in `mcpEnabled`.
   */
  async refresh(servers: McpServerConfig[], force: boolean = false,
    includeDisabled: boolean = false): Promise<McpServerStatus[]> {
    const enabled: McpServerConfig[] = [];
    const disabled: string[] = [];
    for (let i = 0; i < servers.length; i++) {
      if (servers[i].enabled) {
        enabled.push(servers[i]);
      } else {
        disabled.push(servers[i].id);
      }
    }
    if (includeDisabled) {
      for (let i = 0; i < servers.length; i++) {
        if (!servers[i].enabled) {
          enabled.push(servers[i]);
        }
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
    this.globallyDisabled = disabled;
    return statuses;
  }

  definitions(disabledTools: string[], disabledServers: string[] = [],
    enabledServers: string[] = []): ToolDefinition[] {
    const out: ToolDefinition[] = [];
    for (let i = 0; i < this.tools.length; i++) {
      const info: McpToolInfo = this.tools[i];
      if (disabledTools.indexOf(info.exposedName) >= 0) {
        continue;
      }
      if (disabledServers.indexOf(info.serverId) >= 0) {
        continue;
      }
      if (this.globallyDisabled.indexOf(info.serverId) >= 0 &&
        enabledServers.indexOf(info.serverId) < 0) {
        continue;
      }
      out.push(definitionFor(info));
    }
    return out;
  }

  /** True when the last discovery saw the server's global switch off. */
  isGloballyDisabled(serverId: string): boolean {
    return this.globallyDisabled.indexOf(serverId) >= 0;
  }

  /** Owning server id, or an empty string when the name is not an MCP tool. */
  serverIdOf(exposedName: string): string {
    for (let i = 0; i < this.tools.length; i++) {
      if (this.tools[i].exposedName === exposedName) {
        return this.tools[i].serverId;
      }
    }
    return '';
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
        return { ok: false, content: t('MCP 服务未连接：') + info.serverName };
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
  private disabledServers: string[];
  private enabledServers: string[];

  constructor(
    inner: ToolRuntime,
    disabledTools: string[],
    disabledServers: string[] = [],
    enabledServers: string[] = []
  ) {
    this.inner = inner;
    this.disabledTools = disabledTools;
    this.disabledServers = disabledServers;
    this.enabledServers = enabledServers;
  }

  definitions(): ToolDefinition[] {
    const base: ToolDefinition[] = this.inner.definitions();
    const extra: ToolDefinition[] = McpRegistry.definitions(
      this.disabledTools, this.disabledServers, this.enabledServers);
    for (let i = 0; i < extra.length; i++) {
      base.push(extra[i]);
    }
    return base;
  }

  async execute(name: string, argumentsJson: string): Promise<ToolResult> {
    const serverId: string = McpRegistry.serverIdOf(name);
    if (serverId.length > 0 && this.disabledServers.indexOf(serverId) >= 0) {
      return { ok: false, content: t('该 MCP 服务已在本会话关闭。') };
    }
    if (serverId.length > 0 && McpRegistry.isGloballyDisabled(serverId) &&
      this.enabledServers.indexOf(serverId) < 0) {
      return { ok: false, content: t('该 MCP 服务已在全局关闭。') };
    }
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
