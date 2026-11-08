/**
 * Conversion between the internal parts model and the OpenAI chat-completion
 * wire format. This is where assistant tool calls and their results are
 * expanded into the `assistant.tool_calls` + `tool` message pair the API
 * expects.
 */

import {
  ChatMessage,
  PART_IMAGE,
  PART_REASONING,
  PART_TEXT,
  PART_TOOL_CALL,
  TOOL_DONE,
  TOOL_ERROR,
  textOf
} from './Types';

export interface ApiToolFunction {
  name: string;
  arguments: string;
}

export interface ApiToolCall {
  id: string;
  type: string;
  function: ApiToolFunction;
}

export interface ApiImageUrl {
  url: string;
}

/** OpenAI multimodal content part: text or image_url. */
export interface ApiContentPart {
  type: string;
  text?: string;
  image_url?: ApiImageUrl;
}

export interface ApiMessage {
  role: string;
  content: string | ApiContentPart[];
  tool_calls?: ApiToolCall[];
  tool_call_id?: string;
}

/**
 * Turns a workspace-relative image into a data URL. Injected by the agent
 * runtime so this module stays free of file-system access.
 */
export type ImageResolver = (uri: string, mimeType: string) => string;

const INTERRUPTED_RESULT: string = '工具调用在上一轮被中断，未执行。';

function callId(partId: string, fallback: string): string {
  return partId.length > 0 ? partId : fallback;
}

/**
 * Duplicate ids in imported or interrupted histories would make the API pair a
 * result with the wrong call. The first occurrence keeps its id; later ones get
 * a numeric suffix and the matching tool message uses the same suffixed id.
 */
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
 * Convert persisted history into request messages. Reasoning parts are omitted:
 * they are display-only and not accepted by every OpenAI-compatible model.
 */
export function toApiMessages(
  messages: ChatMessage[],
  resolveImage: ImageResolver | null = null
): ApiMessage[] {
  const out: ApiMessage[] = [];
  const usedIds: string[] = [];
  for (let i = 0; i < messages.length; i++) {
    const message: ChatMessage = messages[i];
    if (message.role === 'tool') {
      // Reserved for imported histories; the current model stores results on
      // the assistant turn instead.
      continue;
    }
    const text: string = textOf(message);
    const calls: ApiToolCall[] = [];
    const results: ApiMessage[] = [];
    const images: string[] = [];
    for (let j = 0; j < message.parts.length; j++) {
      const part = message.parts[j];
      if (part.kind !== PART_TOOL_CALL || part.toolName.trim().length === 0) {
        continue;
      }
      const id: string = uniqueCallId(
        callId(part.toolCallId, 'call_' + i + '_' + j), usedIds);
      const args: string = part.argumentsText.length > 0 ? part.argumentsText : '{}';
      calls.push({
        id: id,
        type: 'function',
        function: { name: part.toolName, arguments: args }
      });
      let result: string = part.resultText;
      if (result.length === 0 &&
        part.status !== TOOL_DONE && part.status !== TOOL_ERROR) {
        result = INTERRUPTED_RESULT;
      }
      results.push({
        role: 'tool',
        content: result,
        tool_call_id: id
      });
      let dataUrl: string = '';
      if (resolveImage !== null && part.uri.length > 0) {
        dataUrl = resolveImage(part.uri, part.mimeType);
      }
      images.push(dataUrl);
    }

    if (message.role === 'assistant') {
      if (text.length === 0 && calls.length === 0) {
        continue;
      }
      const assistant: ApiMessage = { role: 'assistant', content: text };
      if (calls.length > 0) {
        assistant.tool_calls = calls;
      }
      out.push(assistant);
      for (let k = 0; k < results.length; k++) {
        out.push(results[k]);
        if (images[k].length > 0) {
          // The Chat Completions schema does not allow image parts inside a
          // role:"tool" message, so the pixels follow as a synthetic user turn.
          const parts: ApiContentPart[] = [
            { type: 'text', text: '以下是 read_image 读取的图片：' },
            { type: 'image_url', image_url: { url: images[k] } }
          ];
          out.push({ role: 'user', content: parts });
        }
      }
    } else if (message.role === 'user' || message.role === 'system') {
      const imageUrls: string[] = [];
      if (message.role === 'user' && resolveImage !== null) {
        for (let j = 0; j < message.parts.length; j++) {
          const part = message.parts[j];
          if (part.kind === PART_IMAGE && part.uri.length > 0) {
            const dataUrl: string = resolveImage(part.uri, part.mimeType);
            if (dataUrl.length > 0) {
              imageUrls.push(dataUrl);
            }
          }
        }
      }
      if (imageUrls.length === 0) {
        if (text.length === 0) {
          continue;
        }
        out.push({ role: message.role, content: text });
      } else {
        const parts: ApiContentPart[] = [];
        if (text.length > 0) {
          parts.push({ type: 'text', text: text });
        }
        for (let j = 0; j < imageUrls.length; j++) {
          parts.push({ type: 'image_url', image_url: { url: imageUrls[j] } });
        }
        out.push({ role: message.role, content: parts });
      }
    }
  }
  return out;
}

/** True when a turn contains at least one tool call part. */
export function hasToolCalls(message: ChatMessage): boolean {
  for (let i = 0; i < message.parts.length; i++) {
    if (message.parts[i].kind === PART_TOOL_CALL) {
      return true;
    }
  }
  return false;
}

/** Text used by tests and diagnostics. */
export function describeParts(message: ChatMessage): string {
  const kinds: string[] = [];
  for (let i = 0; i < message.parts.length; i++) {
    const part = message.parts[i];
    if (part.kind === PART_TEXT || part.kind === PART_REASONING) {
      kinds.push(part.kind + '(' + part.text.length + ')');
    } else {
      kinds.push(part.kind + ':' + part.toolName + ':' + part.status);
    }
  }
  return kinds.join(',');
}
