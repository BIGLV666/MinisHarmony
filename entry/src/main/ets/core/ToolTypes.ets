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
}

export interface ToolResult {
  ok: boolean;
  content: string;
}

/**
 * The pluggable sandbox boundary. `LocalToolRuntime` executes inside the app
 * sandbox; `RemoteToolRuntime` forwards the same calls to a helper process
 * (PC/NAS/VPS). A future QEMU runtime implements the same two methods.
 */
export interface ToolRuntime {
  definitions(): ToolDefinition[];
  execute(name: string, argumentsJson: string): Promise<ToolResult>;
}

/**
 * Optional capability behind `subagent_task`. Implemented by SubagentRunner;
 * the local runtime only advertises the tool when a handler is supplied.
 */
export interface SubagentHandler {
  run(prompt: string, label: string): Promise<ToolResult>;
}
