/**
 * Anthropic Messages API conversion and streaming-event decoding.
 *
 * The app stores conversations as parts, so this module expands an assistant
 * turn with tool calls into `tool_use` blocks plus a synthetic user turn of
 * `tool_result` blocks. Tool results must directly follow the assistant turn
 * that requested them, which is why the results are emitted immediately after
 * each assistant message instead of in a later user turn.
 *
 * Pure functions only: no HarmonyOS imports, so scripts/test-core.mjs can
 * exercise the conversion and the SSE decoder under Node.
 */

import {
  ChatMessage,
  PART_IMAGE,
  PART_TEXT,
  PART_TOOL_CALL,
  TOOL_DONE,
  TOOL_ERROR,
  textOf
} from './Types';
import { ImageResolver } from './ToolProtocol';
import { ToolDefinition } from './ToolTypes';
import { DeltaResult, ToolCallDelta, emptyDelta } from './SseParser';
import { t } from './I18n';

export const ANTHROPIC_VERSION: string = '2023-06-01';
export const ANTHROPIC_DEFAULT_BASE: string = 'https://api.anthropic.com/v1';
export const ANTHROPIC_DEFAULT_MODEL: string = 'claude-sonnet-5-5';

function interruptedResult(): string {
  return t('工具调用在上一轮被中断，未执行。');
}

export interface AnthropicImageSource {
  type: string;
  media_type: string;
  data: string;
}

export interface AnthropicBlock {
  type: string;
  text?: string;
  source?: AnthropicImageSource;
  id?: string;
  name?: string;
  input?: Object;
  tool_use_id?: string;
  content?: string | AnthropicBlock[];
  is_error?: boolean;
}

export interface AnthropicMessage {
  role: string;
  content: AnthropicBlock[];
}

export interface AnthropicToolDefinition {
  name: string;
  description: string;
  input_schema: Object;
}

export interface AnthropicMessages {
  system: string;
  messages: AnthropicMessage[];
}

export interface AnthropicRequestBody {
  model: string;
  max_tokens: number;
  messages: AnthropicMessage[];
  stream: boolean;
  system?: string;
  temperature?: number;
  top_p?: number;
  tools?: AnthropicToolDefinition[];
}

/** Parse a `data:<mime>;base64,<payload>` URL into an image block. */
export function imageBlock(dataUrl: string): AnthropicBlock | null {
  if (dataUrl === null || dataUrl === undefined || dataUrl.length === 0) {
    return null;
  }
  const lower: string = dataUrl.toLowerCase();
  if (lower.indexOf('data:') !== 0) {
    return null;
  }
  const comma: number = dataUrl.indexOf(',');
  if (comma < 0) {
    return null;
  }
  const header: string = dataUrl.substring(5, comma);
  if (header.toLowerCase().indexOf(';base64') < 0) {
    return null;
  }
  const semicolon: number = header.indexOf(';');
  const mime: string = semicolon > 0 ? header.substring(0, semicolon) : 'image/png';
  const data: string = dataUrl.substring(comma + 1);
  if (data.length === 0) {
    return null;
  }
  return {
    type: 'image',
    source: { type: 'base64', media_type: mime, data: data }
  };
}

function pushBlocks(out: AnthropicMessage[], role: string, blocks: AnthropicBlock[]): void {
  if (blocks.length === 0) {
    return;
  }
  if (out.length > 0 && out[out.length - 1].role === role) {
    const previous: AnthropicMessage = out[out.length - 1];
    for (let i = 0; i < blocks.length; i++) {
      previous.content.push(blocks[i]);
    }
    return;
  }
  out.push({ role: role, content: blocks });
}

function parseArguments(text: string): Object {
  const source: string = text.trim().length === 0 ? '{}' : text;
  try {
    return JSON.parse(source) as Object;
  } catch (e) {
    return JSON.parse('{}') as Object;
  }
}

function uniqueCallId(raw: string, used: string[]): string {
  let id: string = raw;
  let attempt: number = 2;
  while (used.indexOf(id) >= 0) {
    id = raw + '_' + attempt.toString();
    attempt++;
  }
  used.push(id);
  return id;
}

/**
 * Convert stored history into Messages API turns. The top-level system prompt
 * is assembled by the caller; `system`-role messages inside the history (for
 * example a `/compact` summary) become user text so no content is lost.
 */
export function buildAnthropicMessages(
  history: ChatMessage[],
  resolveImage: ImageResolver | null = null
): AnthropicMessages {
  const out: AnthropicMessage[] = [];
  const usedIds: string[] = [];
  const idByKey: Map<string, string> = new Map<string, string>();

  for (let i = 0; i < history.length; i++) {
    const message: ChatMessage = history[i];
    const calls = message.parts;
    for (let j = 0; j < calls.length; j++) {
      const part = calls[j];
      if (part.kind !== PART_TOOL_CALL || part.toolName.trim().length === 0) {
        continue;
      }
      const raw: string = part.toolCallId.length > 0
        ? part.toolCallId
        : 'call_' + i.toString() + '_' + j.toString();
      idByKey.set(i.toString() + ':' + j.toString(), uniqueCallId(raw, usedIds));
    }
  }

  for (let i = 0; i < history.length; i++) {
    const message: ChatMessage = history[i];
    if (message.role === 'tool') {
      continue;
    }
    const text: string = textOf(message);
    const toolUse: AnthropicBlock[] = [];
    const toolResults: AnthropicBlock[] = [];
    for (let j = 0; j < message.parts.length; j++) {
      const part = message.parts[j];
      if (part.kind !== PART_TOOL_CALL || part.toolName.trim().length === 0) {
        continue;
      }
      const raw: string = part.toolCallId.length > 0
        ? part.toolCallId
        : 'call_' + i.toString() + '_' + j.toString();
      const mapped: string | undefined = idByKey.get(i.toString() + ':' + j.toString());
      const id: string = mapped !== undefined ? mapped : raw;
      toolUse.push({
        type: 'tool_use',
        id: id,
        name: part.toolName,
        input: parseArguments(part.argumentsText)
      });
      let result: string = part.resultText;
      let isError: boolean = part.isError || part.status === TOOL_ERROR;
      if (result.length === 0 &&
        part.status !== TOOL_DONE && part.status !== TOOL_ERROR) {
        result = interruptedResult();
        isError = true;
      }
      const contentBlocks: AnthropicBlock[] = [{ type: 'text', text: result }];
      if (resolveImage !== null && part.uri.length > 0) {
        const image: AnthropicBlock | null = imageBlock(resolveImage(part.uri, part.mimeType));
        if (image !== null) {
          contentBlocks.push(image);
        }
      }
      toolResults.push({
        type: 'tool_result',
        tool_use_id: id,
        content: contentBlocks,
        is_error: isError
      });
    }

    if (message.role === 'assistant') {
      const blocks: AnthropicBlock[] = [];
      if (text.length > 0) {
        blocks.push({ type: 'text', text: text });
      }
      for (let j = 0; j < toolUse.length; j++) {
        blocks.push(toolUse[j]);
      }
      if (blocks.length === 0) {
        continue;
      }
      // Messages API conversations must start with a user turn.
      if (out.length === 0) {
        pushBlocks(out, 'user', [{ type: 'text', text: t('以下是此前的对话：') }]);
      }
      pushBlocks(out, 'assistant', blocks);
      pushBlocks(out, 'user', toolResults);
    } else {
      const blocks: AnthropicBlock[] = [];
      if (text.length > 0) {
        blocks.push({ type: 'text', text: text });
      }
      if (resolveImage !== null && (message.role === 'user' || message.role === 'system')) {
        for (let j = 0; j < message.parts.length; j++) {
          const part = message.parts[j];
          if (part.kind !== PART_IMAGE || part.uri.length === 0) {
            continue;
          }
          const image: AnthropicBlock | null = imageBlock(resolveImage(part.uri, part.mimeType));
          if (image !== null) {
            blocks.push(image);
          }
        }
      }
      if (blocks.length === 0) {
        continue;
      }
      // Anthropic has no system role inside messages; keep the content as a
      // user turn rather than dropping it.
      pushBlocks(out, 'user', blocks);
    }
  }
  return { system: '', messages: out };
}

/** Convert tool definitions into Messages API `input_schema` objects. */
export function anthropicTools(tools: ToolDefinition[]): AnthropicToolDefinition[] {
  const out: AnthropicToolDefinition[] = [];
  for (let i = 0; i < tools.length; i++) {
    let schema: Object = tools[i].parameters;
    const raw: string | undefined = tools[i].schemaJson;
    if (raw !== undefined && raw.length > 0) {
      try {
        schema = JSON.parse(raw) as Object;
      } catch (e) {
        schema = tools[i].parameters;
      }
    }
    out.push({
      name: tools[i].name,
      description: tools[i].description,
      input_schema: schema
    });
  }
  return out;
}

export function buildAnthropicBody(
  model: string,
  maxTokens: number,
  system: string,
  messages: AnthropicMessage[],
  tools: AnthropicToolDefinition[],
  temperature: number,
  topP: number
): AnthropicRequestBody {
  const body: AnthropicRequestBody = {
    model: model,
    max_tokens: maxTokens,
    messages: messages,
    stream: true
  };
  if (system.length > 0) {
    body.system = system;
  }
  if (temperature >= 0) {
    // Messages API accepts 0–1; the app's generic slider allows up to 2.
    body.temperature = temperature > 1 ? 1 : temperature;
  }
  if (topP > 0) {
    body.top_p = topP;
  }
  if (tools.length > 0) {
    body.tools = tools;
  }
  return body;
}

/** True for a base URL that already points at the messages endpoint. */
export function anthropicMessagesUrl(raw: string): string {
  const base: string = raw.trim().replace(/\/+$/, '');
  if (base.endsWith('/messages')) {
    return base;
  }
  return base + '/messages';
}

/** Model discovery lives beside `/messages` on the same API base. */
export function anthropicModelsUrl(raw: string): string {
  let base: string = raw.trim().replace(/\/+$/, '');
  if (base.endsWith('/messages')) {
    base = base.substring(0, base.length - '/messages'.length);
  }
  return base + '/models';
}

// ---------------------------------------------------------------------------
// Streaming events
// ---------------------------------------------------------------------------

export interface AnthropicStreamState {
  inputTokens: number;
  outputTokens: number;
  sawUsage: boolean;
}

export function newAnthropicStreamState(): AnthropicStreamState {
  return { inputTokens: 0, outputTokens: 0, sawUsage: false };
}

interface AnthropicUsagePayload {
  input_tokens?: number;
  output_tokens?: number;
}

interface AnthropicErrorPayload {
  type?: string;
  message?: string;
}

interface AnthropicContentBlockPayload {
  type?: string;
  id?: string;
  name?: string;
  text?: string;
}

interface AnthropicDeltaPayload {
  type?: string;
  text?: string;
  thinking?: string;
  partial_json?: string;
  stop_reason?: string;
}

interface AnthropicMessagePayload {
  usage?: AnthropicUsagePayload;
}

interface AnthropicEventPayload {
  type?: string;
  index?: number;
  message?: AnthropicMessagePayload;
  content_block?: AnthropicContentBlockPayload;
  delta?: AnthropicDeltaPayload;
  usage?: AnthropicUsagePayload;
  error?: AnthropicErrorPayload;
}

/** Map Anthropic stop reasons onto the app's OpenAI-shaped finish reasons. */
export function anthropicFinishReason(reason: string): string {
  if (reason === 'tool_use') {
    return 'tool_calls';
  }
  if (reason === 'max_tokens') {
    return 'length';
  }
  if (reason === 'refusal') {
    return 'content_filter';
  }
  if (reason === 'end_turn' || reason === 'stop_sequence' || reason === 'pause_turn') {
    return 'stop';
  }
  return reason;
}

function numberOrZero(value: number | undefined): number {
  return value !== undefined && value > 0 ? value : 0;
}

/**
 * Decode one SSE `data:` payload. `state` carries cumulative usage across
 * events because the API reports input tokens once and output tokens later.
 */
export function parseAnthropicData(
  data: string,
  state: AnthropicStreamState
): DeltaResult {
  const result: DeltaResult = emptyDelta();
  const raw: string = data.trim();
  if (raw.length === 0) {
    return result;
  }
  if (raw === '[DONE]') {
    result.done = true;
    return result;
  }
  let payload: AnthropicEventPayload;
  try {
    payload = JSON.parse(raw) as AnthropicEventPayload;
  } catch (e) {
    result.error = t('无法解析流式响应');
    return result;
  }
  const kind: string = typeof payload.type === 'string' ? payload.type : '';

  if (kind === 'error') {
    const detail: AnthropicErrorPayload | undefined = payload.error;
    const message: string = detail !== undefined && detail !== null &&
      typeof detail.message === 'string' ? detail.message : '';
    result.error = message.length > 0 ? message : t('模型返回了错误事件');
    return result;
  }

  if (kind === 'message_start') {
    const usage: AnthropicUsagePayload | undefined =
      payload.message !== undefined && payload.message !== null
        ? payload.message.usage : undefined;
    if (usage !== undefined && usage !== null) {
      state.inputTokens = numberOrZero(usage.input_tokens);
      state.sawUsage = true;
    }
  } else if (kind === 'content_block_start') {
    const block: AnthropicContentBlockPayload | undefined = payload.content_block;
    if (block !== undefined && block !== null && block.type === 'tool_use') {
      const delta: ToolCallDelta = {
        index: typeof payload.index === 'number' ? payload.index : 0,
        id: typeof block.id === 'string' ? block.id : '',
        name: typeof block.name === 'string' ? block.name : '',
        arguments: ''
      };
      result.toolCalls.push(delta);
    }
  } else if (kind === 'content_block_delta') {
    const delta: AnthropicDeltaPayload | undefined = payload.delta;
    if (delta !== undefined && delta !== null) {
      if (delta.type === 'text_delta' && typeof delta.text === 'string') {
        result.content = delta.text;
      } else if (delta.type === 'thinking_delta' && typeof delta.thinking === 'string') {
        result.reasoning = delta.thinking;
      } else if (delta.type === 'input_json_delta' && typeof delta.partial_json === 'string') {
        const call: ToolCallDelta = {
          index: typeof payload.index === 'number' ? payload.index : 0,
          id: '',
          name: '',
          arguments: delta.partial_json
        };
        result.toolCalls.push(call);
      }
    }
  } else if (kind === 'message_delta') {
    const delta: AnthropicDeltaPayload | undefined = payload.delta;
    if (delta !== undefined && delta !== null && typeof delta.stop_reason === 'string') {
      result.finishReason = anthropicFinishReason(delta.stop_reason);
    }
    const usage: AnthropicUsagePayload | undefined = payload.usage;
    if (usage !== undefined && usage !== null) {
      state.outputTokens = numberOrZero(usage.output_tokens);
      state.sawUsage = true;
    }
  } else if (kind === 'message_stop') {
    result.done = true;
  }

  if (state.sawUsage) {
    result.usage.present = true;
    result.usage.promptTokens = state.inputTokens;
    result.usage.completionTokens = state.outputTokens;
    result.usage.totalTokens = state.inputTokens + state.outputTokens;
  }
  return result;
}
