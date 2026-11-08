import { t } from './I18n';
/**
 * Incremental Server-Sent Events parser plus OpenAI chat-completion chunk
 * decoding. Pure functions only, so the same file runs under Node's type
 * stripping in scripts/test-core.mjs.
 */

export interface SseEvent {
  event: string;
  data: string;
}

export interface OpenAiToolFunctionDelta {
  name?: string;
  arguments?: string;
}

export interface OpenAiToolCallDelta {
  index?: number;
  id?: string;
  type?: string;
  function?: OpenAiToolFunctionDelta;
}

export interface OpenAiDelta {
  content?: string;
  reasoning_content?: string;
  reasoning?: string;
  tool_calls?: OpenAiToolCallDelta[];
}

/** One streamed fragment of a tool call. */
export interface ToolCallDelta {
  index: number;
  id: string;
  name: string;
  arguments: string;
}

export interface OpenAiChoice {
  delta?: OpenAiDelta;
  finish_reason?: string;
}

export interface OpenAiErrorDetail {
  message?: string;
  type?: string;
  code?: string;
}

export interface OpenAiUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
  total_tokens?: number;
}

export interface OpenAiStreamChunk {
  choices?: OpenAiChoice[];
  usage?: OpenAiUsage;
  error?: OpenAiErrorDetail;
}

/** Token counts reported by the provider; `present` is false when absent. */
export interface TokenUsage {
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  present: boolean;
}

export interface DeltaResult {
  content: string;
  reasoning: string;
  done: boolean;
  finishReason: string;
  error: string;
  toolCalls: ToolCallDelta[];
  usage: TokenUsage;
}

export interface ErrorEnvelope {
  error?: OpenAiErrorDetail;
  message?: string;
}

export function emptyDelta(): DeltaResult {
  return {
    content: '',
    reasoning: '',
    done: false,
    finishReason: '',
    error: '',
    toolCalls: [],
    usage: {
      promptTokens: 0,
      completionTokens: 0,
      totalTokens: 0,
      present: false
    }
  };
}

/**
 * Feed arbitrary decoded text chunks; get back complete SSE events.
 * Handles CRLF, multiple data lines, comments, and events split across
 * network chunks. Call flush() once the stream ends.
 */
export class SseParser {
  private buffer: string = '';

  push(chunk: string): SseEvent[] {
    this.buffer += chunk;
    // Normalising at the buffer level also repairs a CRLF split across chunks.
    this.buffer = this.buffer.split('\r\n').join('\n');
    const events: SseEvent[] = [];
    let separator: number = this.buffer.indexOf('\n\n');
    while (separator >= 0) {
      const block: string = this.buffer.substring(0, separator);
      this.buffer = this.buffer.substring(separator + 2);
      const event: SseEvent | null = this.parseBlock(block);
      if (event !== null) {
        events.push(event);
      }
      separator = this.buffer.indexOf('\n\n');
    }
    return events;
  }

  flush(): SseEvent[] {
    const events: SseEvent[] = [];
    if (this.buffer.trim().length > 0) {
      const event: SseEvent | null = this.parseBlock(this.buffer);
      if (event !== null) {
        events.push(event);
      }
    }
    this.buffer = '';
    return events;
  }

  private parseBlock(block: string): SseEvent | null {
    if (block.trim().length === 0) {
      return null;
    }
    const lines: string[] = block.split('\n');
    let eventName: string = 'message';
    const dataLines: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i];
      if (line.startsWith(':')) {
        continue;
      }
      if (line.startsWith('event:')) {
        eventName = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.push(line.substring(5).trim());
      }
    }
    if (dataLines.length === 0) {
      return null;
    }
    return { event: eventName, data: dataLines.join('\n') };
  }
}

export function parseOpenAiData(data: string): DeltaResult {
  const result: DeltaResult = emptyDelta();
  if (data === '[DONE]') {
    result.done = true;
    return result;
  }
  let chunk: OpenAiStreamChunk;
  try {
    chunk = JSON.parse(data) as OpenAiStreamChunk;
  } catch (e) {
    return result;
  }
  if (chunk.error !== undefined && chunk.error !== null) {
    // JSON null survives a `!== undefined` test, so check the type itself.
    result.error = typeof chunk.error.message === 'string' && chunk.error.message.length > 0
      ? chunk.error.message
      : t('服务端返回错误');
    result.done = true;
    return result;
  }
  // Usage arrives on a final chunk whose `choices` array is empty when the
  // request sets `stream_options.include_usage`. Some providers send
  // `"usage": null` on intermediate chunks, which must not be dereferenced.
  if (chunk.usage !== undefined && chunk.usage !== null) {
    const prompt: number = typeof chunk.usage.prompt_tokens === 'number'
      ? chunk.usage.prompt_tokens
      : 0;
    const completion: number = typeof chunk.usage.completion_tokens === 'number'
      ? chunk.usage.completion_tokens
      : 0;
    const total: number = typeof chunk.usage.total_tokens === 'number'
      ? chunk.usage.total_tokens
      : prompt + completion;
    result.usage = {
      promptTokens: prompt,
      completionTokens: completion,
      totalTokens: total,
      present: true
    };
  }
  if (chunk.choices === undefined || chunk.choices === null || chunk.choices.length === 0) {
    return result;
  }
  const choice: OpenAiChoice = chunk.choices[0];
  if (choice === undefined || choice === null) {
    return result;
  }
  if (typeof choice.finish_reason === 'string') {
    result.finishReason = choice.finish_reason;
  }
  if (choice.delta === undefined || choice.delta === null) {
    return result;
  }
  const delta: OpenAiDelta = choice.delta;
  // `"content": null` and `"reasoning": null` are common on intermediate
  // chunks. Assigning them would leave a null in a string-typed field and
  // crash the `.length` checks in ChatApi.consumeEvent.
  if (typeof delta.content === 'string') {
    result.content = delta.content;
  }
  if (typeof delta.reasoning_content === 'string') {
    result.reasoning = delta.reasoning_content;
  } else if (typeof delta.reasoning === 'string') {
    result.reasoning = delta.reasoning;
  }
  if (delta.tool_calls !== undefined && delta.tool_calls !== null) {
    for (let i = 0; i < delta.tool_calls.length; i++) {
      const item: OpenAiToolCallDelta = delta.tool_calls[i];
      if (item === undefined || item === null) {
        continue;
      }
      let index: number = 0;
      if (typeof item.index === 'number') {
        index = item.index;
      }
      let id: string = '';
      let name: string = '';
      let args: string = '';
      if (typeof item.id === 'string') {
        id = item.id;
      }
      if (item.function !== undefined && item.function !== null) {
        if (typeof item.function.name === 'string') {
          name = item.function.name;
        }
        if (typeof item.function.arguments === 'string') {
          args = item.function.arguments;
        }
      }
      result.toolCalls.push({
        index: index,
        id: id,
        name: name,
        arguments: args
      });
    }
  }
  return result;
}

/** Best-effort extraction of a human-readable message from an error body. */
export function parseErrorMessage(raw: string): string {
  const text: string = raw.trim();
  if (text.length === 0) {
    return '';
  }
  try {
    const envelope: ErrorEnvelope = JSON.parse(text) as ErrorEnvelope;
    if (envelope.error !== undefined && envelope.error !== null &&
      typeof envelope.error.message === 'string' && envelope.error.message.length > 0) {
      return envelope.error.message;
    }
    if (typeof envelope.message === 'string' && envelope.message.length > 0) {
      return envelope.message;
    }
  } catch (e) {
    // Not JSON: fall through to the raw body.
  }
  if (text.length > 280) {
    return text.substring(0, 280) + t('…');
  }
  return text;
}
