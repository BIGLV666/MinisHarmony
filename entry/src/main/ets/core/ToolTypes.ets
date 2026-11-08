/**
 * Tool protocol types shared by the agent loop, the local runtime and the
 * remote runtime. Pure interfaces only; safe to run under Node.
 */

export interface ToolProperty {
  type: string;
  description: string;
}

export interface ToolParameters {
  type: string;
  properties: Record<string, ToolProperty>;
  required: string[];
}

export interface ToolDefinition {
  name: string;
  description: string;
  parameters: ToolParameters;
  /**
   * Raw JSON Schema for tools whose schema is richer than `ToolParameters`
   * (MCP servers can return nested objects, enums and arrays). When present
   * it is sent instead of `parameters`.
   */
  schemaJson?: string;
}

export interface ToolResult {
  ok: boolean;
  content: string;
  /** Workspace-relative image path; the runtime turns it into a data URL. */
  imageUri?: string;
  imageMimeType?: string;
}

/**
 * The pluggable sandbox boundary. `LocalToolRuntime` executes inside the app
 * sandbox; `RemoteToolRuntime` forwards the same calls to a helper process
 * (PC/NAS/VPS). A future QEMU runtime implements the same two methods.
 */
export interface ToolRuntime {
  definitions(): ToolDefinition[];
  execute(name: string, argumentsJson: string): Promise<ToolResult>;
  /** Build a data URL for a workspace image; empty when unavailable. */
  imageDataUrl(uri: string, mimeType: string): string;
}

/** One call of the single `subagent_task` tool. */
export interface SubagentRequest {
  /** delegate (default), status, steer, cancel or resume. */
  action: string;
  prompt: string;
  label: string;
  jobId: string;
  message: string;
  /** Only delegate: false returns at once and posts the result later. */
  wait: boolean;
  /** Wall-clock budget, clamped by the handler. */
  maxMinutes: number;
}

/**
 * Optional capability behind `subagent_task`. Implemented by SubagentRunner;
 * the local runtime only advertises the tool when a handler is supplied.
 */
export interface SubagentHandler {
  execute(request: SubagentRequest): Promise<ToolResult>;
}

/** One image-generation request, already validated by the caller. */
export interface ImageGenRequest {
  prompt: string;
  size: string;
  model: string;
}

/** Pluggable image generation so the tool runtime never holds API keys. */
export interface ImageGenHandler {
  generate(request: ImageGenRequest): Promise<ToolResult>;
}

/**
 * Optional capability behind `browser_use`. Implemented by a handler bound to
 * the hidden ArkWeb view; the runtime only advertises the tool when present.
 */
export interface BrowserHandler {
  execute(argumentsJson: string): Promise<ToolResult>;
}

/**
 * Optional capability behind `shell_execute`. Implemented by ShellTool, which
 * owns the local iSH sandbox session; the runtime only advertises the tool
 * when a handler is supplied.
 */
export interface ShellHandler {
  execute(argumentsJson: string): Promise<ToolResult>;
}

/**
 * Device-data tools (calendar / contacts / location / weather). Each tool is
 * advertised only when the handler both exists and reports it enabled, so the
 * user's per-capability switches remove it from the model's toolbox entirely.
 */
export interface DeviceToolsHandler {
  enabled(name: string): boolean;
  execute(name: string, argumentsJson: string): Promise<ToolResult>;
}
