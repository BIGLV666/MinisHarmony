/**
 * Google Gemini `generateContent` protocol conversion.
 *
 * Gemini differs from both OpenAI and Anthropic: turns use roles `user` and
 * `model`, tool calls are `functionCall` parts without ids, and tool results
 * are `functionResponse` parts inside a user turn. Images travel as inline
 * base64 data. This module builds requests and decodes `alt=sse` stream
 * chunks into the app's shared DeltaResult shape.
 *
 * Pure functions only, so scripts/test-core.mjs can exercise them under Node.
 */

import {
  ChatMessage,
  PART_IMAGE,
  PART_TOOL_CALL,
  TOOL_DONE,
  TOOL_ERROR,
  textOf
} from './Types';
import { ImageResolver } from './ToolProtocol';
import { ToolDefinition } from './ToolTypes';
import { DeltaResult, ToolCallDelta, emptyDelta } from './SseParser';
import { t } from './I18n';

export const GEMINI_DEFAULT_BASE: string = 'https://generativelanguage.googleapis.com/v1beta';
export const GEMINI_DEFAULT_MODEL: string = 'gemini-2.5-pro';

function interruptedResult(): string {
  return t('工具调用在上一轮被中断，未执行。');
}

export interface GeminiInlineData {
  mimeType: string;
  data: string;
}

export interface GeminiFunctionCall {
  name: string;
  args?: Object;
}

export interface GeminiFunctionResponsePayload {
  result?: string;
  error?: string;
}

export interface GeminiFunctionResponse {
  name: string;
  response: GeminiFunctionResponsePayload;
}

export interface GeminiPart {
  text?: string;
  inlineData?: GeminiInlineData;
  functionCall?: GeminiFunctionCall;
  functionResponse?: GeminiFunctionResponse;
  thought?: boolean;
}

export interface GeminiContent {
  role: string;
  parts: GeminiPart[];
}

export interface GeminiSystemInstruction {
  parts: GeminiPart[];
}

export interface GeminiFunctionDeclaration {
  name: string;
  description: string;
  parameters: Object;
}

export interface GeminiTool {
  functionDeclarations: GeminiFunctionDeclaration[];
}

export interface GeminiGenerationConfig {
  temperature?: number;
  topP?: number;
  maxOutputTokens?: number;
}

export interface GeminiRequestBody {
  contents: GeminiContent[];
  systemInstruction?: GeminiSystemInstruction;
  tools?: GeminiTool[];
  generationConfig?: GeminiGenerationConfig;
}

export interface GeminiMessages {
  system: string;
  contents: GeminiContent[];
}

export interface GeminiInlineResult {
  mimeType: string;
  data: string;
}

/** Split a `data:<mime>;base64,<payload>` URL; null for anything else. */
export function geminiInlineData(dataUrl: string): GeminiInlineResult | null {
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
  return { mimeType: mime, data: data };
}

function parseArguments(text: string): Object {
  const source: string = text.trim().length === 0 ? '{}' : text;
  try {
    return JSON.parse(source) as Object;
  } catch (e) {
    return JSON.parse('{}') as Object;
  }
}

/** Gemini rejects consecutive same-role turns in some SDK paths; merge them. */
function pushParts(out: GeminiContent[], role: string, parts: GeminiPart[]): void {
  if (parts.length === 0) {
    return;
  }
  if (out.length > 0 && out[out.length - 1].role === role) {
    const previous: GeminiContent = out[out.length - 1];
    for (let i = 0; i < parts.length; i++) {
      previous.parts.push(parts[i]);
    }
    return;
  }
  out.push({ role: role, parts: parts });
}

/**
 * Convert stored history into Gemini contents. Tool calls become
 * `functionCall` parts on the model turn and `functionResponse` parts on the
 * immediately following user turn. A leading model turn gets a short user
 * preamble because Gemini expects the conversation to start with a user turn.
 */
export function buildGeminiContents(
  history: ChatMessage[],
  resolveImage: ImageResolver | null = null
): GeminiMessages {
  const out: GeminiContent[] = [];
  for (let i = 0; i < history.length; i++) {
    const message: ChatMessage = history[i];
    if (message.role === 'tool') {
      continue;
    }
    const text: string = textOf(message);
    const calls: GeminiPart[] = [];
    const results: GeminiPart[] = [];
    for (let j = 0; j < message.parts.length; j++) {
      const part = message.parts[j];
      if (part.kind !== PART_TOOL_CALL || part.toolName.trim().length === 0) {
        continue;
      }
      calls.push({
        functionCall: {
          name: part.toolName,
          args: parseArguments(part.argumentsText)
        }
      });
      let result: string = part.resultText;
      let isError: boolean = part.isError || part.status === TOOL_ERROR;
      if (result.length === 0 &&
        part.status !== TOOL_DONE && part.status !== TOOL_ERROR) {
        result = interruptedResult();
        isError = true;
      }
      results.push({
        functionResponse: {
          name: part.toolName,
          response: isError ? { error: result } : { result: result }
        }
      });
    }

    if (message.role === 'assistant') {
      const parts: GeminiPart[] = [];
      if (text.length > 0) {
        parts.push({ text: text });
      }
      for (let j = 0; j < calls.length; j++) {
        parts.push(calls[j]);
      }
      if (parts.length === 0) {
        continue;
      }
      if (out.length === 0) {
        pushParts(out, 'user', [{ text: t('以下是此前的对话：') }]);
      }
      pushParts(out, 'model', parts);
      pushParts(out, 'user', results);
    } else {
      const parts: GeminiPart[] = [];
      if (text.length > 0) {
        parts.push({ text: text });
      }
      if (resolveImage !== null) {
        for (let j = 0; j < message.parts.length; j++) {
          const part = message.parts[j];
          if (part.kind !== PART_IMAGE || part.uri.length === 0) {
            continue;
          }
          const inline: GeminiInlineResult | null =
            geminiInlineData(resolveImage(part.uri, part.mimeType));
          if (inline !== null) {
            parts.push({
              inlineData: { mimeType: inline.mimeType, data: inline.data }
            });
          }
        }
      }
      if (parts.length === 0) {
        continue;
      }
      // Gemini has no system role inside contents; keep the text as a user turn.
      pushParts(out, 'user', parts);
    }
  }
  return { system: '', contents: out };
}

export function geminiTools(tools: ToolDefinition[]): GeminiTool[] {
  if (tools.length === 0) {
    return [];
  }
  const declarations: GeminiFunctionDeclaration[] = [];
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
    declarations.push({
      name: tools[i].name,
      description: tools[i].description,
      parameters: schema
    });
  }
  return [{ functionDeclarations: declarations }];
}

export function buildGeminiBody(
  model: string,
  maxTokens: number,
  system: string,
  contents: GeminiContent[],
  tools: GeminiTool[],
  temperature: number,
  topP: number
): GeminiRequestBody {
  const config: GeminiGenerationConfig = { maxOutputTokens: maxTokens };
  if (temperature >= 0) {
    config.temperature = temperature;
  }
  if (topP > 0) {
    config.topP = topP;
  }
  const body: GeminiRequestBody = {
    contents: contents,
    generationConfig: config
  };
  if (system.length > 0) {
    body.systemInstruction = { parts: [{ text: system }] };
  }
  if (tools.length > 0) {
    body.tools = tools;
  }
  // `model` is part of the URL, not the body; kept in the signature so the
  // caller cannot forget which model the request belongs to.
  return body;
}

function stripStreamSuffix(base: string): string {
  let value: string = base;
  const query: number = value.indexOf('?');
  if (query >= 0) {
    value = value.substring(0, query);
  }
  const generate: string = ':generateContent';
  const stream: string = ':streamGenerateContent';
  if (value.endsWith(stream)) {
    value = value.substring(0, value.length - stream.length);
  } else if (value.endsWith(generate)) {
    value = value.substring(0, value.length - generate.length);
  }
  return value;
}

/** True when the base already names one model, e.g. `.../models/gemini-x`. */
function namesModel(base: string): boolean {
  const marker: number = base.indexOf('/models/');
  return marker >= 0 && base.substring(marker + '/models/'.length).length > 0;
}

/** `base/models/<id>:streamGenerateContent?alt=sse` */
export function geminiStreamUrl(raw: string, model: string): string {
  const base: string = stripStreamSuffix(raw.trim().replace(/\/+$/, ''));
  const suffix: string = ':streamGenerateContent?alt=sse';
  if (namesModel(base)) {
    return base + suffix;
  }
  const id: string = model.trim();
  if (base.endsWith('/models')) {
    return base + '/' + id + suffix;
  }
  return base + '/models/' + id + suffix;
}

/** `base/models/<id>:generateContent` for non-streaming summarisation. */
export function geminiGenerateUrl(raw: string, model: string): string {
  const base: string = stripStreamSuffix(raw.trim().replace(/\/+$/, ''));
  const suffix: string = ':generateContent';
  if (namesModel(base)) {
    return base + suffix;
  }
  const id: string = model.trim();
  if (base.endsWith('/models')) {
    return base + '/' + id + suffix;
  }
  return base + '/models/' + id + suffix;
}

/** Model discovery lives at `<api-base>/models`; a full model URL is trimmed. */
export function geminiModelsUrl(raw: string): string {
  let base: string = stripStreamSuffix(raw.trim().replace(/\/+$/, ''));
  const marker: number = base.indexOf('/models/');
  if (marker >= 0) {
    base = base.substring(0, marker);
  }
  if (base.endsWith('/models')) {
    return base;
  }
  return base + '/models';
}

// ---------------------------------------------------------------------------
// Streaming events
// ---------------------------------------------------------------------------

export interface GeminiStreamState {
  promptTokens: number;
  completionTokens: number;
  sawUsage: boolean;
  nextToolIndex: number;
}

export function newGeminiStreamState(): GeminiStreamState {
  return {
    promptTokens: 0,
    completionTokens: 0,
    sawUsage: false,
    nextToolIndex: 0
  };
}

interface GeminiUsageMetadata {
  promptTokenCount?: number;
  candidatesTokenCount?: number;
  totalTokenCount?: number;
}

interface GeminiCandidatePayload {
  content?: GeminiContent;
  finishReason?: string;
}

interface GeminiErrorBody {
  code?: number;
  message?: string;
  status?: string;
}

interface GeminiPromptFeedback {
  blockReason?: string;
}

interface GeminiStreamEnvelope {
  candidates?: GeminiCandidatePayload[];
  usageMetadata?: GeminiUsageMetadata;
  promptFeedback?: GeminiPromptFeedback;
  error?: GeminiErrorBody;
}

export function geminiFinishReason(reason: string): string {
  if (reason === 'MAX_TOKENS') {
    return 'length';
  }
  if (reason === 'SAFETY' || reason === 'RECITATION' ||
    reason === 'BLOCKLIST' || reason === 'PROHIBITED_CONTENT' ||
    reason === 'SPII') {
    return 'content_filter';
  }
  if (reason === 'STOP' || reason === 'FINISH_REASON_UNSPECIFIED' ||
    reason === 'OTHER' || reason.length === 0) {
    return 'stop';
  }
  return reason.toLowerCase();
}

function tokenCount(value: number | undefined): number {
  return value !== undefined && value > 0 ? value : 0;
}

/** Decode one `data:` payload from `:streamGenerateContent?alt=sse`. */
export function parseGeminiData(
  data: string,
  state: GeminiStreamState
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
  let envelope: GeminiStreamEnvelope;
  try {
    envelope = JSON.parse(raw) as GeminiStreamEnvelope;
  } catch (e) {
    result.error = t('无法解析流式响应');
    return result;
  }
  if (envelope.error !== undefined && envelope.error !== null) {
    const message: string = typeof envelope.error.message === 'string'
      ? envelope.error.message : '';
    result.error = message.length > 0 ? message : t('模型返回了错误');
    return result;
  }
  if (envelope.promptFeedback !== undefined && envelope.promptFeedback !== null &&
    typeof envelope.promptFeedback.blockReason === 'string' &&
    envelope.promptFeedback.blockReason.length > 0) {
    result.error = t('请求被安全策略拦截（') + envelope.promptFeedback.blockReason + t('）');
    return result;
  }

  const usage: GeminiUsageMetadata | undefined = envelope.usageMetadata;
  if (usage !== undefined && usage !== null) {
    state.promptTokens = tokenCount(usage.promptTokenCount);
    state.completionTokens = tokenCount(usage.candidatesTokenCount);
    state.sawUsage = true;
  }

  const candidates: GeminiCandidatePayload[] | undefined = envelope.candidates;
  if (candidates !== undefined && candidates !== null && candidates.length > 0) {
    const candidate: GeminiCandidatePayload = candidates[0];
    if (candidate === undefined || candidate === null) {
      return result;
    }
    if (typeof candidate.finishReason === 'string' && candidate.finishReason.length > 0) {
      result.finishReason = geminiFinishReason(candidate.finishReason);
    }
    if (candidate.content !== undefined && candidate.content !== null &&
      candidate.content.parts !== undefined && candidate.content.parts !== null) {
      for (let i = 0; i < candidate.content.parts.length; i++) {
        const part: GeminiPart = candidate.content.parts[i];
        if (part === undefined || part === null) {
          continue;
        }
        if (typeof part.text === 'string' && part.text.length > 0) {
          if (part.thought === true) {
            result.reasoning += part.text;
          } else {
            result.content += part.text;
          }
        }
        if (part.functionCall !== undefined && part.functionCall !== null &&
          typeof part.functionCall.name === 'string' && part.functionCall.name.length > 0) {
          const args: string = part.functionCall.args !== undefined
            ? JSON.stringify(part.functionCall.args) : '{}';
          const call: ToolCallDelta = {
            index: state.nextToolIndex,
            id: 'call_' + state.nextToolIndex.toString(),
            name: part.functionCall.name,
            arguments: args
          };
          state.nextToolIndex++;
          result.toolCalls.push(call);
        }
      }
    }
  }

  if (state.sawUsage) {
    result.usage.present = true;
    result.usage.promptTokens = state.promptTokens;
    result.usage.completionTokens = state.completionTokens;
    result.usage.totalTokens = state.promptTokens + state.completionTokens;
  }
  return result;
}
