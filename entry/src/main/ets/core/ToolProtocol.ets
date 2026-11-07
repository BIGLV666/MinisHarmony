/**
 * Conversion between the internal parts model and the OpenAI chat-completion
 * wire format. This is where assistant tool calls and their results are
 * expanded into the `assistant.tool_calls` + `tool` message pair the API
 * expects.
 */

import {
  ChatMessage,
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

export interface ApiMessage {
  role: string;
  content: string;
  tool_calls?: ApiToolCall[];
  tool_call_id?: string;
}

const INTERRUPTED_RESULT: string = '工具调用在上一轮被中断，未执行。';

function callId(partId: string, fallback: string): string {
  return partId.length > 0 ? partId : fallback;
}

/**
 * Convert persisted history into request messages. Reasoning parts are omitted:
 * they are display-only and not accepted by every OpenAI-compatible model.
 */
export function toApiMessages(messages: ChatMessage[]): ApiMessage[] {
  const out: ApiMessage[] = [];
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
    for (let j = 0; j < message.parts.length; j++) {
      const part = message.parts[j];
      if (part.kind !== PART_TOOL_CALL) {
        continue;
      }
      const id: string = callId(part.toolCallId, 'call_' + i + '_' + j);
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
      }
    } else if (message.role === 'user' || message.role === 'system') {
      if (text.length === 0) {
        continue;
      }
      out.push({ role: message.role, content: text });
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
