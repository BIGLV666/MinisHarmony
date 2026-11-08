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

/**
 * Optional capability behind `subagent_task`. Implemented by SubagentRunner;
 * the local runtime only advertises the tool when a handler is supplied.
 */
export interface SubagentHandler {
  run(prompt: string, label: string): Promise<ToolResult>;
}
