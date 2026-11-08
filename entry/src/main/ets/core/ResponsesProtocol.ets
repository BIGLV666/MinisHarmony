/**
 * OpenAI Responses API wire format, used by the ChatGPT Codex OAuth path.
 *
 * Everything here is pure: request conversion, endpoint derivation and the
 * SSE event decoder. The transport (http, headers, cancellation) stays in
 * `service/ChatApi.ets`, and the token lifecycle stays in `service/OAuth.ets`,
 * so the format can be tested without a device or an account.
 *
 * The Responses API differs from Chat Completions in three ways that matter:
 * the system prompt is a top-level `instructions` string, tools are flat
 * `{type, name, description, parameters}` objects, and the transcript is a
 * list of typed items (`message`, `function_call`, `function_call_output`)
 * rather than role/tool_calls pairs.
 */

import { ApiContentPart, ApiMessage, ApiToolCall } from './ToolProtocol';
import { ToolDefinition } from './ToolTypes';
import { DeltaResult, TokenUsage, ToolCallDelta, emptyDelta } from './SseParser';

/** The Codex backend mount point; the inference route hangs off it. */
export const CODEX_API_BASE: string = 'https://chatgpt.com/backend-api/codex';
/** Client identity the ChatGPT backend validates the request against. */
export const CODEX_CLIENT_VERSION: string = '0.155.0';
export const CODEX_USER_AGENT: string =
  'codex_cli_rs/' + CODEX_CLIENT_VERSION + ' (Android; arm64)';
/** Models the OAuth route has accepted; discovery is preferred when online. */
export const CODEX_FALLBACK_MODELS: string[] = [
  'gpt-6-sol',
  'gpt-6-luna',
  'gpt-6-astra',
  'gpt-5.6-sol',
  'gpt-5.6-terra',
  'gpt-5.6-luna',
  'gpt-5.5',
  'gpt-5.4',
  'gpt-5.4-mini'
];

/** Responses ids must be at most 64 characters. */
const MAX_ID_CHARS: number = 64;

export interface ResponsesContentPart {
  type: string;
  text?: string;
  /** Responses takes a plain string here, unlike Chat Completions' object. */
  image_url?: string;
}

export interface ResponsesInputItem {
  type?: string;
  role?: string;
  content?: string | ResponsesContentPart[];
  id?: string;
  call_id?: string;
  name?: string;
  arguments?: string;
  output?: string;
}

export interface ResponsesToolDefinition {
  type: string;
  name: string;
  description: string;
  parameters: Object;
  strict?: boolean;
}

export interface ResponsesReasoning {
  effort: string;
  summary: string;
}

export interface ResponsesRequestBody {
  model: string;
  instructions?: string;
  input: ResponsesInputItem[];
  stream: boolean;
  store: boolean;
  parallel_tool_calls: boolean;
  include?: string[];
  reasoning?: ResponsesReasoning;
  tools?: ResponsesToolDefinition[];
  tool_choice?: string;
  prompt_cache_key?: string;
  service_tier?: string;
}

/** `/responses` for a Codex base (`.../codex`), a full URL, or a proxy root. */
export function responsesUrl(raw: string): string {
  const base: string = raw.trim().replace(/\/+$/, '');
  if (base.endsWith('/responses')) {
    return base;
  }
  return base + '/responses';
}

/** `/models` for the Codex discovery route (not the `/v1/models` route). */
export function codexModelsUrl(raw: string): string {
  let base: string = raw.trim().replace(/\/+$/, '');
  if (base.endsWith('/models')) {
    return base;
  }
  if (base.endsWith('/responses')) {
    base = base.substring(0, base.length - '/responses'.length);
  }
  return base + '/models';
}

function clipId(value: string): string {
  return value.length > MAX_ID_CHARS ? value.substring(0, MAX_ID_CHARS) : value;
}

/** Tool call ids store `call_id|item_id` so the next turn can echo both. */
export function combineResponsesIds(callId: string, itemId: string): string {
  return itemId.length === 0 ? callId : callId + '|' + itemId;
}

export function callIdPart(combined: string): string {
  const bar: number = combined.indexOf('|');
  return bar >= 0 ? combined.substring(0, bar) : combined;
}

function itemIdPart(combined: string): string {
  const bar: number = combined.indexOf('|');
  return bar >= 0 ? combined.substring(bar + 1) : '';
}

/** The system prompt is a single top-level string, not an input item. */
export function responsesInstructions(messages: ApiMessage[]): string {
  const parts: string[] = [];
  for (let i = 0; i < messages.length; i++) {
    const message: ApiMessage = messages[i];
    if (message.role !== 'system') {
      continue;
    }
    if (typeof message.content === 'string' && message.content.length > 0) {
      parts.push(message.content);
    }
  }
  return parts.join('\n\n');
}

function contentPart(part: ApiContentPart): ResponsesContentPart | null {
  if (part.type === 'text') {
    const text: string = part.text !== undefined ? part.text : '';
    return text.length > 0 ? { type: 'input_text', text: text } : null;
  }
  if (part.type === 'image_url' && part.image_url !== undefined) {
    return { type: 'input_image', image_url: part.image_url.url };
  }
  return null;
}

function userItem(message: ApiMessage): ResponsesInputItem | null {
  if (typeof message.content === 'string') {
    if (message.content.length === 0) {
      return null;
    }
    return { role: 'user', content: message.content };
  }
  const parts: ResponsesContentPart[] = [];
  for (let i = 0; i < message.content.length; i++) {
    const converted: ResponsesContentPart | null = contentPart(message.content[i]);
    if (converted !== null) {
      parts.push(converted);
    }
  }
  if (parts.length === 0) {
    return null;
  }
  return { role: 'user', content: parts };
}

function functionCallItem(call: ApiToolCall): ResponsesInputItem {
  const combined: string = call.id;
  const callId: string = clipId(callIdPart(combined));
  let itemId: string = itemIdPart(combined);
  if (itemId.length === 0) {
    // Synthesised histories (imported or from another provider) have no
    // `fc_` item id; the backend still wants one, so derive a stable value.
    itemId = 'fc_syn_' + callId;
  }
  const args: string = call.function.arguments.length > 0
    ? call.function.arguments : '{}';
  return {
    type: 'function_call',
    id: clipId(itemId),
    call_id: callId,
    name: call.function.name,
    arguments: args
  };
}

/**
 * Convert Chat-Completions-shaped messages into Responses input items. Input
 * comes from `toApiMessages`, so duplicate-id handling and tool-result text
 * are shared with the other protocols.
 */
export function buildResponsesInput(messages: ApiMessage[]): ResponsesInputItem[] {
  const out: ResponsesInputItem[] = [];
  for (let i = 0; i < messages.length; i++) {
    const message: ApiMessage = messages[i];
    if (message.role === 'system') {
      continue;
    }
    if (message.role === 'user') {
      const item: ResponsesInputItem | null = userItem(message);
      if (item !== null) {
        out.push(item);
      }
      continue;
    }
    if (message.role === 'assistant') {
      const text: string = typeof message.content === 'string' ? message.content : '';
      if (text.length > 0) {
        out.push({ role: 'assistant', content: text });
      }
      const calls: ApiToolCall[] | undefined = message.tool_calls;
      if (calls !== undefined) {
        for (let j = 0; j < calls.length; j++) {
          out.push(functionCallItem(calls[j]));
        }
      }
      continue;
    }
    if (message.role === 'tool') {
      const callId: string = message.tool_call_id !== undefined
        ? clipId(callIdPart(message.tool_call_id)) : '';
      const output: string = typeof message.content === 'string' ? message.content : '';
      out.push({ type: 'function_call_output', call_id: callId, output: output });
    }
  }
  return out;
}

/** Flat tool objects, unlike Chat Completions' `{type, function:{...}}`. */
export function buildResponsesTools(tools: ToolDefinition[]): ResponsesToolDefinition[] {
  const out: ResponsesToolDefinition[] = [];
  for (let i = 0; i < tools.length; i++) {
    let parameters: Object = tools[i].parameters;
    const raw: string | undefined = tools[i].schemaJson;
    if (raw !== undefined && raw.length > 0) {
      try {
        parameters = JSON.parse(raw) as Object;
      } catch (e) {
        parameters = tools[i].parameters;
      }
    }
    out.push({
      type: 'function',
      name: tools[i].name,
      description: tools[i].description,
      parameters: parameters,
      strict: false
    });
  }
  return out;
}

/**
 * A stable cache key for one conversation. The API caches prompt prefixes per
 * key; hashing the first user text keeps turns of the same chat together and
 * separate chats apart without storing anything.
 */
export function promptCacheKey(messages: ApiMessage[]): string {
  let seed: string = '';
  for (let i = 0; i < messages.length; i++) {
    if (messages[i].role === 'user' && typeof messages[i].content === 'string' &&
      messages[i].content.length > 0) {
      seed = messages[i].content as string;
      break;
    }
  }
  if (seed.length === 0) {
    return '';
  }
  let hash: number = 0;
  for (let i = 0; i < seed.length; i++) {
    hash = (hash * 31 + seed.charCodeAt(i)) | 0;
  }
  return 'minis-' + (hash >>> 0).toString(16);
}

// ---------------------------------------------------------------------------
// Streaming events
// ---------------------------------------------------------------------------

export interface ResponsesStreamState {
  nextToolIndex: number;
  /** item id (`fc_…`) -> stable tool index for this turn. */
  toolIndexByItem: Map<string, number>;
  /** How many argument characters were already emitted per item. */
  argLengthByItem: Map<string, number>;
  /** True when `output_item.added` already supplied the function name. */
  nameSentByItem: Map<string, boolean>;
  sawToolCall: boolean;
  sawText: boolean;
  promptTokens: number;
  completionTokens: number;
}

export function newResponsesStreamState(): ResponsesStreamState {
  return {
    nextToolIndex: 0,
    toolIndexByItem: new Map<string, number>(),
    argLengthByItem: new Map<string, number>(),
    nameSentByItem: new Map<string, boolean>(),
    sawToolCall: false,
    sawText: false,
    promptTokens: 0,
    completionTokens: 0
  };
}

interface ResponsesUsage {
  input_tokens?: number;
  output_tokens?: number;
  total_tokens?: number;
}

interface ResponsesOutputItem {
  id?: string;
  type?: string;
  call_id?: string;
  name?: string;
  arguments?: string;
}

interface ResponsesError {
  code?: string;
  message?: string;
}

interface ResponsesPayload {
  usage?: ResponsesUsage;
  error?: ResponsesError;
  status?: string;
  incomplete_details?: ResponsesIncomplete;
}

interface ResponsesIncomplete {
  reason?: string;
}

interface ResponsesEvent {
  type?: string;
  delta?: string;
  item_id?: string;
  item?: ResponsesOutputItem;
  response?: ResponsesPayload;
  message?: string;
  code?: string;
  error?: ResponsesError;
}

function count(value: number | undefined): number {
  return typeof value === 'number' && value > 0 ? Math.floor(value) : 0;
}

function errorMessage(code: string, message: string): string {
  const detail: string = message.length > 0 ? message : '模型返回了错误';
  return code.length > 0 ? '[' + code + '] ' + detail : detail;
}

function appliedUsage(state: ResponsesStreamState): TokenUsage {
  return {
    promptTokens: state.promptTokens,
    completionTokens: state.completionTokens,
    totalTokens: state.promptTokens + state.completionTokens,
    present: true
  };
}

function itemIndex(state: ResponsesStreamState, itemId: string): number {
  const known: number | undefined = state.toolIndexByItem.get(itemId);
  if (known !== undefined) {
    return known;
  }
  const index: number = state.nextToolIndex;
  state.nextToolIndex++;
  state.toolIndexByItem.set(itemId, index);
  state.argLengthByItem.set(itemId, 0);
  state.nameSentByItem.set(itemId, false);
  return index;
}

export function parseResponsesData(data: string, state: ResponsesStreamState): DeltaResult {
  const result: DeltaResult = emptyDelta();
  const raw: string = data.trim();
  if (raw.length === 0) {
    return result;
  }
  if (raw === '[DONE]') {
    result.done = true;
    return result;
  }
  let event: ResponsesEvent;
  try {
    event = JSON.parse(raw) as ResponsesEvent;
  } catch (e) {
    result.error = '无法解析流式响应';
    return result;
  }
  const type: string = typeof event.type === 'string' ? event.type : '';
  if (type === 'error') {
    const code: string = event.code !== undefined && typeof event.code === 'string'
      ? event.code : '';
    const message: string = event.message !== undefined && typeof event.message === 'string'
      ? event.message : '';
    const nested: string = event.error !== undefined && event.error !== null &&
      typeof event.error.message === 'string' ? event.error.message : '';
    result.error = errorMessage(code, message.length > 0 ? message : nested);
    return result;
  }

  if (type === 'response.output_text.delta') {
    const delta: string = typeof event.delta === 'string' ? event.delta : '';
    if (delta.length > 0) {
      result.content = delta;
      state.sawText = true;
    }
    return result;
  }
  if (type === 'response.reasoning_text.delta' ||
    type === 'response.reasoning_summary_text.delta') {
    const delta: string = typeof event.delta === 'string' ? event.delta : '';
    if (delta.length > 0) {
      result.reasoning = delta;
    }
    return result;
  }

  if (type === 'response.output_item.added') {
    const item: ResponsesOutputItem | undefined = event.item;
    if (item === undefined || item.type !== 'function_call') {
      return result;
    }
    const itemId: string = typeof item.id === 'string' ? item.id : '';
    const callId: string = typeof item.call_id === 'string' ? item.call_id : '';
    const name: string = typeof item.name === 'string' ? item.name : '';
    if (itemId.length === 0 || name.length === 0) {
      return result;
    }
    const index: number = itemIndex(state, itemId);
    state.nameSentByItem.set(itemId, true);
    state.sawToolCall = true;
    result.toolCalls.push({
      index: index,
      id: combineResponsesIds(callId, itemId),
      name: name,
      arguments: ''
    });
    return result;
  }

  if (type === 'response.function_call_arguments.delta') {
    const itemId: string = typeof event.item_id === 'string' ? event.item_id : '';
    const delta: string = typeof event.delta === 'string' ? event.delta : '';
    if (itemId.length === 0 || delta.length === 0) {
      return result;
    }
    const index: number = itemIndex(state, itemId);
    const previous: number | undefined = state.argLengthByItem.get(itemId);
    state.argLengthByItem.set(itemId, (previous !== undefined ? previous : 0) + delta.length);
    result.toolCalls.push({ index: index, id: '', name: '', arguments: delta });
    return result;
  }

  if (type === 'response.output_item.done') {
    const item: ResponsesOutputItem | undefined = event.item;
    if (item === undefined || item.type !== 'function_call') {
      return result;
    }
    const itemId: string = typeof item.id === 'string' ? item.id : '';
    if (itemId.length === 0) {
      return result;
    }
    const index: number = itemIndex(state, itemId);
    const callId: string = typeof item.call_id === 'string' ? item.call_id : '';
    const name: string = typeof item.name === 'string' ? item.name : '';
    const full: string = typeof item.arguments === 'string' ? item.arguments : '';
    const sent: number | undefined = state.argLengthByItem.get(itemId);
    const emitted: number = sent !== undefined ? sent : 0;
    // Some relays stream arguments only in the final item; replay the missing
    // suffix so the accumulator sees every character exactly once.
    const missing: string = full.length > emitted ? full.substring(emitted) : '';
    const nameSent: boolean | undefined = state.nameSentByItem.get(itemId);
    const delta: ToolCallDelta = {
      index: index,
      id: combineResponsesIds(callId, itemId),
      name: nameSent === true ? '' : name,
      arguments: missing
    };
    state.nameSentByItem.set(itemId, true);
    state.argLengthByItem.set(itemId, full.length > emitted ? full.length : emitted);
    if (delta.name.length > 0 || delta.arguments.length > 0 || delta.id.length > 0) {
      state.sawToolCall = true;
      result.toolCalls.push(delta);
    }
    return result;
  }

  if (type === 'response.completed') {
    const response: ResponsesPayload | undefined = event.response;
    if (response !== undefined && response.usage !== undefined && response.usage !== null) {
      state.promptTokens = count(response.usage.input_tokens);
      state.completionTokens = count(response.usage.output_tokens);
      result.usage = appliedUsage(state);
    }
    result.done = true;
    result.finishReason = state.sawToolCall ? 'tool_calls' : 'stop';
    return result;
  }

  if (type === 'response.incomplete') {
    if (state.sawText) {
      // Keep the partial answer; `length` lets the UI say it was cut short.
      result.done = true;
      result.finishReason = 'length';
    } else {
      result.error = '模型输出被截断';
    }
    return result;
  }

  if (type === 'response.failed') {
    const response: ResponsesPayload | undefined = event.response;
    const code: string = response !== undefined && response.error !== undefined &&
      response.error !== null && typeof response.error.code === 'string'
      ? response.error.code : '';
    const message: string = response !== undefined && response.error !== undefined &&
      response.error !== null && typeof response.error.message === 'string'
      ? response.error.message : '';
    result.error = errorMessage(code, message);
    return result;
  }

  return result;
}
