/**
 * Incremental Server-Sent Events parser plus OpenAI chat-completion chunk
 * decoding. Pure functions only, so the same file runs under Node's type
 * stripping in scripts/test-core.mjs.
 */

export interface SseEvent {
  event: string;
  data: string;
}

export interface OpenAiDelta {
  content?: string;
  reasoning_content?: string;
  reasoning?: string;
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

export interface OpenAiStreamChunk {
  choices?: OpenAiChoice[];
  error?: OpenAiErrorDetail;
}

export interface DeltaResult {
  content: string;
  reasoning: string;
  done: boolean;
  finishReason: string;
  error: string;
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
    error: ''
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
  if (chunk.error !== undefined) {
    result.error = chunk.error.message !== undefined ? chunk.error.message : '服务端返回错误';
    result.done = true;
    return result;
  }
  if (chunk.choices === undefined || chunk.choices.length === 0) {
    return result;
  }
  const choice: OpenAiChoice = chunk.choices[0];
  if (choice.finish_reason !== undefined) {
    result.finishReason = choice.finish_reason;
  }
  if (choice.delta === undefined) {
    return result;
  }
  const delta: OpenAiDelta = choice.delta;
  if (delta.content !== undefined) {
    result.content = delta.content;
  }
  if (delta.reasoning_content !== undefined) {
    result.reasoning = delta.reasoning_content;
  } else if (delta.reasoning !== undefined) {
    result.reasoning = delta.reasoning;
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
    if (envelope.error !== undefined && envelope.error.message !== undefined) {
      return envelope.error.message;
    }
    if (envelope.message !== undefined) {
      return envelope.message;
    }
  } catch (e) {
    // Not JSON: fall through to the raw body.
  }
  if (text.length > 280) {
    return text.substring(0, 280) + '…';
  }
  return text;
}
