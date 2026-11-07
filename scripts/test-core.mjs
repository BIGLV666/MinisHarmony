/**
 * Runs the dependency-free core modules under Node's TypeScript type
 * stripping. ArkTS is a TypeScript dialect, and these files deliberately avoid
 * ArkUI/ohos imports so they can be exercised without DevEco Studio.
 *
 *   node --experimental-strip-types --experimental-transform-types scripts/test-core.mjs
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = dirname(here);
const core = join(root, 'entry/src/main/ets/core');
const tmp = join(here, '.tmp');

rmSync(tmp, { recursive: true, force: true });
mkdirSync(tmp, { recursive: true });

/**
 * ArkTS uses extensionless relative imports; Node's ESM loader does not.
 * Rewrite the few internal imports while copying to .mts.
 */
function copyCore(name, deps = []) {
  let source = readFileSync(join(core, `${name}.ets`), 'utf8');
  for (const dep of deps) {
    source = source.split(`from './${dep}'`).join(`from './${dep}.mts'`);
  }
  writeFileSync(join(tmp, `${name}.mts`), source);
}

copyCore('SseParser');
copyCore('OpenCodeRules');
copyCore('Markdown');
copyCore('Types');
copyCore('ToolTypes');
copyCore('ToolCatalog', ['ToolTypes']);
copyCore('ToolProtocol', ['Types']);
copyCore('Workspace');
copyCore('EventLog');

// ArkTS needs runtime imports for interface types; Node's type stripping
// needs them marked `type` (interfaces have no runtime binding).
function markTypeOnly(name, from, names) {
  const file = join(tmp, `${name}.mts`);
  const source = readFileSync(file, 'utf8');
  const plain = `import { ${names.join(', ')} } from './${from}.mts';`;
  const typed = `import type { ${names.join(', ')} } from './${from}.mts';`;
  writeFileSync(file, source.split(plain).join(typed));
}

markTypeOnly('ToolCatalog', 'ToolTypes', ['ToolDefinition', 'ToolParameters', 'ToolProperty']);

{
  const file = join(tmp, 'ToolProtocol.mts');
  const source = readFileSync(file, 'utf8');
  writeFileSync(
    file,
    source.replace(
      "import {\n  ChatMessage,\n  PART_REASONING,",
      "import type { ChatMessage } from './Types.mts';\nimport {\n  PART_REASONING,"
    )
  );
}

const sse = await import(pathToFileURL(join(tmp, 'SseParser.mts')).href);
const rules = await import(pathToFileURL(join(tmp, 'OpenCodeRules.mts')).href);
const md = await import(pathToFileURL(join(tmp, 'Markdown.mts')).href);
const types = await import(pathToFileURL(join(tmp, 'Types.mts')).href);
const proto = await import(pathToFileURL(join(tmp, 'ToolProtocol.mts')).href);
const workspace = await import(pathToFileURL(join(tmp, 'Workspace.mts')).href);
const log = await import(pathToFileURL(join(tmp, 'EventLog.mts')).href);

test('OpenCode host matching is dot-anchored', () => {
  assert.equal(rules.isOpenCodeBase('https://opencode.ai/inference/go/openai/v1'), true);
  assert.equal(rules.isOpenCodeBase('opencode.ai/zen/go/v1'), true);
  assert.equal(rules.isOpenCodeBase('https://api.opencode.ai/v1'), true);
  assert.equal(rules.isOpenCodeBase('https://not-opencode.ai/v1'), false);
  assert.equal(rules.isOpenCodeBase('https://opencode.ai.example.com/v1'), false);
  assert.equal(rules.isOpenCodeBase('https://example.com/opencode.ai'), false);
});

test('base URL normalization', () => {
  assert.equal(rules.normalizeBaseUrl(' opencode.ai/zen/go/v1/// '), 'https://opencode.ai/zen/go/v1');
  assert.equal(rules.hostOf('HTTP://User@OpenCode.AI:443/v1'), 'opencode.ai');
});

test('chat and model URLs', () => {
  const base = 'https://opencode.ai/inference/go/openai/v1';
  assert.equal(rules.chatCompletionsUrl(base), base + '/chat/completions');
  assert.equal(rules.modelsUrl(base), 'https://opencode.ai/inference/go/v1/models');
  assert.equal(
    rules.modelsUrl('https://opencode.ai/zen/go/v1'),
    'https://opencode.ai/zen/go/v1/models'
  );
  assert.equal(rules.modelsUrl('https://api.example.com/v1'), 'https://api.example.com/v1/models');
  assert.equal(
    rules.chatCompletionsUrl('https://api.example.com/v1/chat/completions'),
    'https://api.example.com/v1/chat/completions'
  );
});

test('session header is only for opencode.ai and persisted ids', () => {
  assert.equal(rules.shouldAttachSessionHeader('https://opencode.ai/inference/go/openai/v1', 'abc'), true);
  assert.equal(rules.shouldAttachSessionHeader('https://not-opencode.ai/v1', 'abc'), false);
  assert.equal(rules.shouldAttachSessionHeader('https://opencode.ai/v1', '__new__123'), false);
  assert.equal(rules.shouldAttachSessionHeader('https://opencode.ai/v1', '   '), false);
});

test('SSE parser reassembles events split across chunks', () => {
  const parser = new sse.SseParser();
  let events = parser.push('data: {"choices":[{"delta":{"con');
  assert.equal(events.length, 0);
  events = parser.push('tent":"你"}}]}\n\n');
  assert.equal(events.length, 1);
  assert.equal(events[0].data, '{"choices":[{"delta":{"content":"你"}}]}');
});

test('SSE parser handles CRLF, comments and multiple data lines', () => {
  const parser = new sse.SseParser();
  const events = parser.push(': keepalive\r\nevent: delta\r\ndata: a\r\ndata: b\r\n\r\n');
  assert.equal(events.length, 1);
  assert.equal(events[0].event, 'delta');
  assert.equal(events[0].data, 'a\nb');
});

test('SSE parser flushes a trailing block', () => {
  const parser = new sse.SseParser();
  parser.push('data: {"choices":[]}');
  const events = parser.flush();
  assert.equal(events.length, 1);
  assert.equal(events[0].data, '{"choices":[]}');
});

test('OpenAI chunk decoding covers content, reasoning, finish and DONE', () => {
  let delta = sse.parseOpenAiData('{"choices":[{"delta":{"content":"hi"}}]}');
  assert.equal(delta.content, 'hi');
  assert.equal(delta.reasoning, '');
  delta = sse.parseOpenAiData('{"choices":[{"delta":{"reasoning_content":"think"}}]}');
  assert.equal(delta.reasoning, 'think');
  delta = sse.parseOpenAiData('{"choices":[{"delta":{},"finish_reason":"stop"}]}');
  assert.equal(delta.finishReason, 'stop');
  delta = sse.parseOpenAiData('[DONE]');
  assert.equal(delta.done, true);
});

test('OpenAI error chunks and error bodies are surfaced', () => {
  const delta = sse.parseOpenAiData('{"error":{"message":"bad model"}}');
  assert.equal(delta.error, 'bad model');
  assert.equal(sse.parseErrorMessage('{"error":{"message":"missing x-opencode-session"}}'), 'missing x-opencode-session');
  assert.equal(sse.parseErrorMessage('{"message":"plain"}'), 'plain');
  assert.equal(sse.parseErrorMessage('upstream exploded'), 'upstream exploded');
  assert.equal(sse.parseErrorMessage(''), '');
});

test('Markdown block parsing', () => {
  const blocks = md.parseMarkdown([
    '# Title',
    '',
    'hello **world**',
    '',
    '- one',
    '- two',
    '',
    '```ts',
    'const a = 1;',
    '```',
    '',
    '> quote'
  ].join('\n'));
  assert.deepEqual(blocks.map((b) => b.kind), [
    md.MdBlockKind.Heading,
    md.MdBlockKind.Paragraph,
    md.MdBlockKind.ListItem,
    md.MdBlockKind.ListItem,
    md.MdBlockKind.Code,
    md.MdBlockKind.Quote
  ]);
  assert.equal(blocks[0].level, 1);
  assert.equal(blocks[4].lang, 'ts');
  assert.equal(blocks[4].text, 'const a = 1;');
});

test('Markdown inline parsing', () => {
  const parts = md.parseInline('a **b** and `c` and [d](https://x.y)');
  assert.equal(parts.some((p) => p.text === 'b' && p.bold), true);
  assert.equal(parts.some((p) => p.text === 'c' && p.code), true);
  assert.equal(parts.some((p) => p.text === 'd' && p.link === 'https://x.y'), true);
});

test('defaults target the canonical Go endpoint and enable tools', () => {
  const settings = types.defaultSettings();
  assert.equal(types.OPENCODE_GO_BASE, 'https://opencode.ai/zen/go/v1');
  assert.equal(settings.baseUrl, types.OPENCODE_GO_BASE);
  assert.equal(settings.toolsEnabled, true);
  assert.equal(settings.allowWriteTools, false);
  assert.equal(settings.sandboxMode, 'local');
  const cloned = types.cloneSettings(settings);
  cloned.apiKey = 'changed';
  assert.equal(settings.apiKey, '');
});

test('message parts keep text and reasoning separate', () => {
  const message = types.newChatMessage('m1', 'assistant', 'hello');
  types.appendText(message, ' world');
  types.appendReasoning(message, 'thinking');
  types.appendText(message, '!');
  assert.equal(types.textOf(message), 'hello world!');
  assert.equal(types.reasoningOf(message), 'thinking');
  assert.deepEqual(message.parts.map((p) => p.kind), [
    types.PART_TEXT,
    types.PART_REASONING,
    types.PART_TEXT
  ]);
  assert.equal(types.messageKey(message).startsWith('m1:0:0'), true);
});

test('appendText starts a new part after a tool call', () => {
  const message = types.newChatMessage('m2', 'assistant', 'before');
  message.parts.push(types.toolCallPart('call_1', 'now', '{}'));
  types.appendText(message, 'after');
  assert.equal(message.parts.length, 3);
  assert.equal(message.parts[2].kind, types.PART_TEXT);
  assert.equal(types.textOf(message), 'beforeafter');
});

test('tool protocol expands calls and results into OpenAI messages', () => {
  const user = types.newChatMessage('u1', 'user', 'read a file');
  const assistant = types.newChatMessage('a1', 'assistant', 'let me look');
  const call = types.toolCallPart('call_1', 'read_file', '{"path":"a.txt"}');
  call.status = types.TOOL_DONE;
  call.resultText = 'contents';
  assistant.parts.push(call);

  const api = proto.toApiMessages([user, assistant]);
  assert.equal(api.length, 3);
  assert.deepEqual(api[0], { role: 'user', content: 'read a file' });
  assert.equal(api[1].role, 'assistant');
  assert.equal(api[1].content, 'let me look');
  assert.equal(api[1].tool_calls.length, 1);
  assert.equal(api[1].tool_calls[0].id, 'call_1');
  assert.equal(api[1].tool_calls[0].type, 'function');
  assert.equal(api[1].tool_calls[0].function.name, 'read_file');
  assert.equal(api[1].tool_calls[0].function.arguments, '{"path":"a.txt"}');
  assert.deepEqual(api[2], {
    role: 'tool',
    content: 'contents',
    tool_call_id: 'call_1'
  });
});

test('interrupted tool calls get a synthetic result', () => {
  const assistant = types.newChatMessage('a2', 'assistant', '');
  const call = types.toolCallPart('', 'now', '');
  call.status = types.TOOL_RUNNING;
  assistant.parts.push(call);

  const api = proto.toApiMessages([assistant]);
  assert.equal(api.length, 2);
  assert.equal(api[0].content, '');
  assert.equal(api[0].tool_calls[0].id, 'call_0_0');
  assert.equal(api[0].tool_calls[0].function.arguments, '{}');
  assert.equal(api[1].role, 'tool');
  assert.equal(api[1].tool_call_id, 'call_0_0');
  assert.match(api[1].content, /中断/);
});

test('empty assistant turns are dropped, reasoning is not sent', () => {
  const empty = types.newChatMessage('a3', 'assistant', '');
  types.appendReasoning(empty, 'internal monologue');
  const assistant = types.newChatMessage('a4', 'assistant', 'answer');
  types.appendReasoning(assistant, 'internal monologue');
  const api = proto.toApiMessages([empty, assistant]);
  assert.deepEqual(api, [{ role: 'assistant', content: 'answer' }]);
});

test('workspace path jail rejects escapes', () => {
  assert.equal(workspace.normalizeRelativePath('../etc/passwd'), null);
  assert.equal(workspace.normalizeRelativePath('/etc/passwd'), null);
  assert.equal(workspace.normalizeRelativePath('a/../b'), null);
  assert.equal(workspace.normalizeRelativePath('..\\boot.ini'), null);
  assert.equal(workspace.normalizeRelativePath('  '), '');
  assert.equal(workspace.normalizeRelativePath('a//b/./c/'), 'a/b/c');
  assert.equal(workspace.normalizeRelativePath('notes\\todo.md'), 'notes/todo.md');
  assert.equal(workspace.resolveWorkspacePath('/data/ws/', 'a/b'), '/data/ws/a/b');
  assert.equal(workspace.resolveWorkspacePath('/data/ws/', ''), '/data/ws');
});

test('truncateText marks long content', () => {
  assert.equal(workspace.truncateText('abc', 10), 'abc');
  const cut = workspace.truncateText('abcdef', 3);
  assert.equal(cut.startsWith('abc\n…'), true);
  assert.match(cut, /6/);
});

test('SSE parser streams tool call fragments', () => {
  const first = sse.parseOpenAiData(JSON.stringify({
    choices: [{
      delta: {
        tool_calls: [{
          index: 0,
          id: 'call_9',
          type: 'function',
          function: { name: 'read_file', arguments: '{"path":"a' }
        }]
      }
    }]
  }));
  assert.equal(first.toolCalls.length, 1);
  assert.equal(first.toolCalls[0].index, 0);
  assert.equal(first.toolCalls[0].id, 'call_9');
  assert.equal(first.toolCalls[0].name, 'read_file');
  assert.equal(first.toolCalls[0].arguments, '{"path":"a');

  const second = sse.parseOpenAiData(JSON.stringify({
    choices: [{
      delta: { tool_calls: [{ index: 0, function: { arguments: '.txt"}' } }] },
      finish_reason: 'tool_calls'
    }]
  }));
  assert.equal(second.toolCalls[0].index, 0);
  assert.equal(second.toolCalls[0].id, '');
  assert.equal(second.toolCalls[0].arguments, '.txt"}');
  assert.equal(second.finishReason, 'tool_calls');

  const plain = sse.parseOpenAiData('{"choices":[{"delta":{"content":"hi"}}]}');
  assert.deepEqual(plain.toolCalls, []);
});

test('agent turn budget is clamped to a safe range', () => {
  assert.equal(types.DEFAULT_MAX_AGENT_TURNS, 200);
  assert.equal(types.clampMaxTurns(200), 200);
  assert.equal(types.clampMaxTurns(0), 1);
  assert.equal(types.clampMaxTurns(-5), 1);
  assert.equal(types.clampMaxTurns(5000), 1000);
  assert.equal(types.clampMaxTurns(12.9), 12);
  assert.equal(types.clampMaxTurns(Number.NaN), 200);
  assert.equal(types.clampMaxTurns(Number.POSITIVE_INFINITY), 200);
  assert.equal(types.clampMaxTurns(undefined), 200);
  const settings = types.defaultSettings();
  assert.equal(settings.maxAgentTurns, 200);
  assert.equal(settings.loggingEnabled, false);
});

test('event log redacts credentials and stays single-line', () => {
  const raw = 'auth Bearer abc.def-123 sk-live_ABCDEFG token=secret123\nnext line';
  const redacted = log.redactSecrets(raw);
  assert.equal(redacted.includes('abc.def-123'), false);
  assert.equal(redacted.includes('sk-live_ABCDEFG'), false);
  assert.equal(redacted.includes('secret123'), false);
  assert.match(redacted, /Bearer \*\*\*/);
  assert.match(redacted, /sk-\*\*\*/);

  const detail = log.sanitizeDetail('line1\nline2\t' + 'x'.repeat(400));
  assert.equal(detail.includes('\n'), false);
  assert.equal(detail.length <= 301, true);
});

test('event log serializes JSONL with a short session tag', () => {
  const event = log.newLogEvent(log.EVENT_MODEL_DONE, log.LOG_INFO);
  event.session = log.sessionTag('1234567890abcdef');
  event.model = 'kimi-k3';
  event.step = 3;
  event.ok = true;
  event.durationMs = 42;
  event.detail = 'finish=stop token=abc';
  const line = log.serializeEvent(event);
  assert.equal(line.endsWith('\n'), true);
  assert.equal(line.trim().split('\n').length, 1);
  const parsed = JSON.parse(line);
  assert.equal(parsed.event, 'model_done');
  assert.equal(parsed.session, '12345678');
  assert.equal(parsed.durationMs, 42);
  assert.equal(parsed.detail.includes('abc'), false);
  assert.equal(parsed.detail.includes('***'), true);

  const date = new Date(2026, 10, 7);
  assert.equal(log.logFileName(date), 'events-2026-11-07.jsonl');
});
