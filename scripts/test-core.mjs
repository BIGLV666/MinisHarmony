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
copyCore('EditPatch');
copyCore('Memory');
copyCore('ContextBudget', ['Types']);
copyCore('MarkdownExport', ['Types']);
copyCore('ToolArgs');
copyCore('ToolLoop');
copyCore('SessionExport', ['Types', 'MarkdownExport']);
copyCore('FileListing');

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
markTypeOnly('SessionExport', 'Types', ['ChatMessage', 'MessagePart', 'StoredSession']);

{
  const file = join(tmp, 'ContextBudget.mts');
  const source = readFileSync(file, 'utf8');
  writeFileSync(
    file,
    source.replace(
      'import {\n  ChatMessage,\n  MessagePart,\n  PART_TOOL_CALL,',
      "import type { ChatMessage, MessagePart } from './Types.mts';\nimport {\n  PART_TOOL_CALL,"
    )
  );
}

{
  const file = join(tmp, 'MarkdownExport.mts');
  const source = readFileSync(file, 'utf8');
  writeFileSync(
    file,
    source.replace(
      'import {\n  ChatMessage,\n  MessagePart,\n  PART_REASONING,\n  PART_TOOL_CALL,\n  StoredSession,\n  modelName,\n  textOf\n} from',
      "import type { ChatMessage, MessagePart, StoredSession } from './Types.mts';\n" +
      "import {\n  PART_REASONING,\n  PART_TOOL_CALL,\n  modelName,\n  textOf\n} from"
    )
  );
}

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
const edit = await import(pathToFileURL(join(tmp, 'EditPatch.mts')).href);
const catalog = await import(pathToFileURL(join(tmp, 'ToolCatalog.mts')).href);
const memory = await import(pathToFileURL(join(tmp, 'Memory.mts')).href);
const budget = await import(pathToFileURL(join(tmp, 'ContextBudget.mts')).href);
const exporter = await import(pathToFileURL(join(tmp, 'MarkdownExport.mts')).href);
const toolArgs = await import(pathToFileURL(join(tmp, 'ToolArgs.mts')).href);
const toolLoop = await import(pathToFileURL(join(tmp, 'ToolLoop.mts')).href);
const sessionExport = await import(pathToFileURL(join(tmp, 'SessionExport.mts')).href);
const listing = await import(pathToFileURL(join(tmp, 'FileListing.mts')).href);

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
  assert.equal(settings.confirmWriteTools, false);
  assert.equal(types.cloneSettings({ ...settings, confirmWriteTools: true }).confirmWriteTools, true);
  assert.equal(settings.sandboxMode, 'local');
  assert.equal(settings.backgroundEnabled, true);
  assert.equal(settings.thinkingLevel, 'off');
  assert.equal(settings.enterToSend, false);
  assert.deepEqual(settings.disabledTools, []);
  assert.equal(settings.onboardingDone, false);
  assert.equal(types.cloneSettings({ ...settings, onboardingDone: true }).onboardingDone, true);
  assert.deepEqual(
    types.normalizeToolNames(['read_file', 'read_file', '', 'now']),
    ['read_file', 'now']
  );
  assert.deepEqual(types.normalizeToolNames(undefined), []);
  assert.equal(catalog.isToolDisabled(['read_file'], 'read_file'), true);
  assert.equal(catalog.isToolDisabled(['read_file'], 'now'), false);
  assert.equal(types.normalizeThinkingLevel('high'), 'high');
  assert.equal(types.normalizeThinkingLevel('bogus'), 'off');
  assert.equal(types.normalizeThinkingLevel(undefined), 'off');
  assert.equal(types.cycleThinkingLevel('off'), 'low');
  assert.equal(types.cycleThinkingLevel('low'), 'medium');
  assert.equal(types.cycleThinkingLevel('medium'), 'high');
  assert.equal(types.cycleThinkingLevel('high'), 'off');
  const legacy = types.cloneSettings({
    ...settings,
    backgroundEnabled: undefined,
    thinkingLevel: undefined,
    enterToSend: undefined
  });
  assert.equal(legacy.backgroundEnabled, true);
  assert.equal(legacy.thinkingLevel, 'off');
  assert.equal(legacy.enterToSend, false);
  assert.equal(types.cloneSettings({ ...settings, enterToSend: true }).enterToSend, true);
  assert.equal(
    types.cloneSettings({ ...settings, thinkingLevel: 'medium' }).thinkingLevel,
    'medium'
  );
  const cloned = types.cloneSettings(settings);
  cloned.apiKey = 'changed';
  assert.equal(settings.apiKey, '');
  cloned.disabledTools.push('now');
  assert.deepEqual(settings.disabledTools, []);
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

test('read_image pixels follow the tool message as a synthetic user turn', () => {
  const assistant = types.newChatMessage('a5', 'assistant', '');
  const call = types.toolCallPart('call_img', 'read_image', '{"path":"pic.png"}');
  call.status = types.TOOL_DONE;
  call.resultText = 'Image loaded successfully.';
  call.uri = 'pic.png';
  call.mimeType = 'image/png';
  assistant.parts.push(call);

  const api = proto.toApiMessages([assistant], (uri, mime) => {
    assert.equal(uri, 'pic.png');
    assert.equal(mime, 'image/png');
    return 'data:image/png;base64,QUJD';
  });
  assert.equal(api.length, 3);
  assert.equal(api[1].role, 'tool');
  assert.equal(api[2].role, 'user');
  assert.equal(Array.isArray(api[2].content), true);
  assert.equal(api[2].content[1].type, 'image_url');
  assert.equal(api[2].content[1].image_url.url, 'data:image/png;base64,QUJD');

  const plain = proto.toApiMessages([assistant]);
  assert.equal(plain.length, 2);
});

test('tool argument repair handles fences, truncation and trailing commas', () => {
  const valid = toolArgs.repairToolArguments('{"path":"a.txt"}');
  assert.equal(valid.text, '{"path":"a.txt"}');
  assert.equal(valid.changed, false);

  const fenced = toolArgs.repairToolArguments('```json\n{"path":"a.txt"}\n```');
  assert.equal(JSON.parse(fenced.text).path, 'a.txt');
  assert.equal(fenced.changed, true);
  assert.equal(fenced.strategy, 'fence');

  const cut = toolArgs.repairToolArguments('{"path":"a.txt"');
  assert.equal(JSON.parse(cut.text).path, 'a.txt');
  assert.match(cut.strategy, /^truncation/);

  const comma = toolArgs.repairToolArguments('{"path":"a.txt",}');
  assert.equal(JSON.parse(comma.text).path, 'a.txt');
  assert.equal(comma.strategy, 'trailing-comma');

  const bad = toolArgs.repairToolArguments('not json');
  assert.equal(bad.text, 'not json');
  assert.equal(bad.changed, false);
  assert.equal(toolArgs.repairToolArguments('').text, '{}');
});

test('tool loop guard counts only consecutive identical calls', () => {
  const guard = new toolLoop.ToolLoopGuard();
  assert.equal(guard.observe('read_file', '{"path":"a"}'), 1);
  assert.equal(guard.observe('read_file', '{"path":"a"}'), 2);
  assert.equal(guard.observe('read_file', '{"path":"b"}'), 1);
  assert.equal(guard.observe('read_file', '{"path":"a"}'), 1);
  assert.equal(guard.observe('read_file', '{"path":"a"}'), 2);
  assert.equal(guard.observe('read_file', '{"path":"a"}'), 3);
  assert.equal(toolLoop.TOOL_LOOP_THRESHOLD, 3);
  assert.match(toolLoop.toolLoopWarning('read_file', 3), /read_file/);
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

test('usage chunks are parsed even when choices is empty', () => {
  const delta = sse.parseOpenAiData(JSON.stringify({
    choices: [],
    usage: { prompt_tokens: 1200, completion_tokens: 34, total_tokens: 1234 }
  }));
  assert.equal(delta.usage.present, true);
  assert.equal(delta.usage.promptTokens, 1200);
  assert.equal(delta.usage.completionTokens, 34);
  assert.equal(delta.usage.totalTokens, 1234);
  assert.equal(delta.content, '');

  const derived = sse.parseOpenAiData(JSON.stringify({
    choices: [],
    usage: { prompt_tokens: 7, completion_tokens: 3 }
  }));
  assert.equal(derived.usage.totalTokens, 10);

  const plain = sse.parseOpenAiData('{"choices":[{"delta":{"content":"x"}}]}');
  assert.equal(plain.usage.present, false);
});

test('searchable text covers messages and tool results', () => {
  const session = {
    meta: { id: 's1', title: 'Config hunting', updatedAt: 0, modelId: 'Kimi-K3', messageCount: 2 },
    messages: []
  };
  const user = types.newChatMessage('u1', 'user', 'Read Config.JSON please');
  const assistant = types.newChatMessage('a1', 'assistant', 'done');
  const call = types.toolCallPart('call_1', 'read_file', '{"path":"config.json"}');
  call.status = types.TOOL_DONE;
  call.resultText = '{"port": 8787}';
  assistant.parts.push(call);
  session.messages.push(user, assistant);

  const blob = types.searchableText(session);
  assert.equal(blob.includes('config.json'), true);
  assert.equal(blob.includes('8787'), true);
  assert.equal(blob.includes('kimi-k3'), true);
  assert.equal(blob, blob.toLowerCase());
  assert.equal(blob.length <= types.SEARCH_BLOB_LIMIT, true);
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
  event.req = 'ab12cd34';
  const line = log.serializeEvent(event);
  assert.equal(line.endsWith('\n'), true);
  assert.equal(line.trim().split('\n').length, 1);
  const parsed = JSON.parse(line);
  assert.equal(parsed.event, 'model_done');
  assert.equal(parsed.session, '12345678');
  assert.equal(parsed.durationMs, 42);
  assert.equal(parsed.req, 'ab12cd34');
  assert.equal(parsed.detail.includes('abc'), false);
  assert.equal(parsed.detail.includes('***'), true);

  const date = new Date(2026, 10, 7);
  assert.equal(log.logFileName(date), 'events-2026-11-07.jsonl');

  const viewed = log.formatEventLine(line);
  assert.match(viewed, /11-08 \d\d:\d\d:\d\d model_done/);
  assert.match(viewed, /42ms/);
  assert.match(viewed, /req=ab12cd34/);
  assert.equal(log.formatEventLine('garbage'), 'garbage');
  assert.equal(log.formatEventLine('  '), '');
});

test('exact edit replaces only a unique anchor', () => {
  const source = 'const a = 1;\nconst b = 2;\n';
  const outcome = edit.applyExactEdit(source, 'const b = 2;', 'const b = 3;', false);
  assert.equal(outcome.ok, true);
  assert.equal(outcome.replacements, 1);
  assert.equal(outcome.content, 'const a = 1;\nconst b = 3;\n');

  const repeated = edit.applyExactEdit('x\nx\n', 'x', 'y', false);
  assert.equal(repeated.ok, false);
  assert.match(repeated.message, /2 次/);
  assert.equal(repeated.content, 'x\nx\n');
});

test('replace_all rewrites every occurrence', () => {
  const outcome = edit.applyExactEdit('a-b-a-b-a', 'a', 'z', true);
  assert.equal(outcome.ok, true);
  assert.equal(outcome.replacements, 3);
  assert.equal(outcome.content, 'z-b-z-b-z');
  assert.equal(edit.countOccurrences('aaaa', 'aa'), 2);
});

test('exact edit rejects empty, identical and missing anchors', () => {
  const empty = edit.applyExactEdit('abc', '', 'x', false);
  assert.equal(empty.ok, false);
  const same = edit.applyExactEdit('abc', 'abc', 'abc', false);
  assert.equal(same.ok, false);
  const missing = edit.applyExactEdit('abc', 'zzz', 'x', false);
  assert.equal(missing.ok, false);
  assert.match(missing.message, /没有找到/);
  assert.equal(missing.content, 'abc');
});

test('memory entries are one line and timestamped', () => {
  const date = new Date(2026, 10, 8, 9, 5);
  assert.equal(memory.dayKey(date), '2026-11-08');
  assert.equal(memory.clockKey(date), '09:05');
  const entry = memory.memoryEntry(date, '用户偏好\n深色模式');
  assert.equal(entry, '- 09:05 用户偏好 深色模式');
  assert.equal(entry.includes('\n'), false);
  assert.equal(memory.oneLine('x'.repeat(600)).length, memory.MEMORY_ENTRY_CHARS + 1);
  assert.equal(memory.isEditableMemoryFile('GLOBAL.md'), true);
  assert.equal(memory.isEditableMemoryFile('2026-11-08.md'), true);
  assert.equal(memory.isEditableMemoryFile('../GLOBAL.md'), false);
  assert.equal(memory.isEditableMemoryFile('notes.md'), false);
  assert.equal(memory.isEditableMemoryFile('2026-11-08.md.bak'), false);
});

test('memory search ranks lines by matched terms', () => {
  const files = [
    { name: '2026-11-08.md', text: '- 09:05 用户偏好深色模式\n- 10:00 项目使用 ArkTS' },
    { name: 'GLOBAL.md', text: '- 用户在上海，使用鸿蒙平板' }
  ];
  const hit = memory.searchMemoryFiles(files, '用户', 10);
  assert.equal(hit.includes('深色模式'), true);
  assert.equal(hit.includes('上海'), true);
  const two = memory.searchMemoryFiles(files, '用户 鸿蒙', 10);
  assert.equal(two.split('\n')[0].includes('上海'), true);
  const none = memory.searchMemoryFiles(files, '不存在', 10);
  assert.match(none, /没有找到/);
  const recent = memory.searchMemoryFiles(files, '', 2);
  assert.equal(recent.split('\n').length, 2);
});

test('memory context is headed and capped', () => {
  const files = [{ name: '2026-11-08.md', text: '- hello' }];
  const context = memory.buildMemoryContext(files, 1000);
  assert.match(context, /^## 长期记忆/);
  assert.match(context, /### 2026-11-08/);
  const capped = memory.buildMemoryContext(
    [{ name: 'big.md', text: 'x'.repeat(5000) }], 200
  );
  assert.equal(capped.length < 400, true);
  assert.equal(memory.buildMemoryContext([], 100), '');
});

test('tool catalogue exposes file_edit with a safe schema', () => {
  const tools = catalog.builtinToolDefinitions();
  const owner = tools.find((tool) => tool.name === 'file_edit');
  assert.notEqual(owner, undefined);
  assert.deepEqual(owner.parameters.required, ['path', 'old_string', 'new_string']);
  assert.equal(owner.parameters.properties.replace_all.type, 'boolean');
  const subagent = tools.find((tool) => tool.name === 'subagent_task');
  assert.notEqual(subagent, undefined);
  assert.deepEqual(subagent.parameters.required, ['prompt']);
  assert.equal(subagent.parameters.properties.label.type, 'string');
});

test('pinned sessions sort above recency and archive state is independent', () => {
  const meta = (id, updatedAt, pinned, archived) => ({
    id, title: id, updatedAt, modelId: 'm', messageCount: 0, pinned, archived
  });
  const sorted = types.sortSessionMetas([
    meta('old-pinned', 10, true, false),
    meta('new', 300, false, false),
    meta('mid', 200, false, true)
  ]);
  assert.deepEqual(sorted.map((item) => item.id), ['old-pinned', 'new', 'mid']);
});

test('sidebar groups sessions into pinned and relative day buckets', () => {
  const meta = (id, updatedAt, pinned) => ({
    id, title: id, updatedAt, modelId: 'm', messageCount: 0,
    pinned, archived: false
  });
  const now = new Date(2026, 10, 8, 12, 0, 0).getTime();
  const day = 24 * 60 * 60 * 1000;
  const groups = types.groupSessionMetas([
    meta('pin', now - 3 * day, true),
    meta('today', now, false),
    meta('yesterday', now - day, false),
    meta('week', now - 3 * day, false),
    meta('old', now - 10 * day, false)
  ], now);
  assert.deepEqual(groups.map((group) => group.label),
    ['置顶', '今天', '昨天', '最近 7 天', '更早']);
  assert.deepEqual(groups.map((group) => group.sessions.map((item) => item.id)), [
    ['pin'], ['today'], ['yesterday'], ['week'], ['old']
  ]);
});

test('rewind keeps the checkpoint and rejects last or missing ids', () => {
  const a = types.newChatMessage('a', 'user', 'first');
  const b = types.newChatMessage('b', 'assistant', 'answer');
  const c = types.newChatMessage('c', 'user', 'second');
  const kept = types.rewindMessages([a, b, c], 'a');
  assert.deepEqual(kept.map((message) => message.id), ['a']);
  assert.equal(types.rewindMessages([a, b, c], 'c'), null);
  assert.equal(types.rewindMessages([a, b, c], 'missing'), null);
  assert.equal(types.rewindMessages([a], 'a'), null);
});

test('compact plans keep the newest user turns and align on a user message', () => {
  const messages = [];
  for (let round = 0; round < 5; round++) {
    messages.push(types.newChatMessage('u' + round, 'user', 'q' + round));
    messages.push(types.newChatMessage('a' + round, 'assistant', 'a' + round));
  }
  const plan = budget.planCompact(messages, 2);
  assert.notEqual(plan, null);
  assert.equal(plan.head.length, 6);
  assert.equal(plan.tail.length, 4);
  assert.equal(plan.tail[0].role, 'user');
  assert.equal(plan.tail[0].id, 'u3');
  assert.equal(budget.planCompact(messages.slice(0, 4), 2), null);
});

test('summary transcript includes tools and respects the character cap', () => {
  const user = types.newChatMessage('u', 'user', '目标：修复登录');
  const assistant = types.newChatMessage('a', 'assistant', '');
  const call = types.toolCallPart('c1', 'read_file', '{"path":"a.ts"}');
  call.resultText = 'R'.repeat(1000);
  assistant.parts.push(call);
  const text = budget.transcriptForSummary([user, assistant], 5000);
  assert.match(text, /用户：目标：修复登录/);
  assert.match(text, /\[工具 read_file\]/);
  const capped = budget.transcriptForSummary([user, assistant], 80);
  assert.equal(capped.length < 160, true);
  const summary = budget.makeSummaryMessage('s1', '要点');
  assert.equal(summary.role, 'system');
  assert.match(types.textOf(summary), /摘要/);
});

test('history budget trims old tool results without touching the transcript', () => {
  const oldUser = types.newChatMessage('u1', 'user', 'go');
  const oldWork = types.newChatMessage('a1', 'assistant', '');
  const call = types.toolCallPart('c1', 'read_file', '{}');
  call.resultText = 'x'.repeat(2000);
  call.status = types.TOOL_DONE;
  oldWork.parts.push(call);
  const messages = [oldUser, oldWork];
  for (let i = 0; i < 6; i++) {
    messages.push(types.newChatMessage('m' + i, 'user', 'filler'));
  }
  const result = budget.fitHistoryToBudget(messages, 1000, 6);
  assert.equal(result.trimmedParts, 1);
  assert.equal(oldWork.parts[0].resultText.length, 2000);
  assert.equal(result.messages[1].parts[0].resultText.length < 800, true);
  assert.match(result.messages[1].parts[0].resultText, /较早的工具结果已省略/);
  const untouched = budget.fitHistoryToBudget(messages, 100000, 6);
  assert.equal(untouched.trimmedParts, 0);
  assert.equal(untouched.messages, messages);
});

test('markdown export renders roles, reasoning and tools with safe file names', () => {
  const user = types.newChatMessage('u1', 'user', '帮我看看配置');
  const assistant = types.newChatMessage('a1', 'assistant', '好的');
  types.appendReasoning(assistant, '先读文件');
  const call = types.toolCallPart('c1', 'read_file', '{"path":"a.txt"}');
  call.resultText = 'hello';
  assistant.parts.push(call);
  const session = {
    meta: {
      id: 's1', title: '导出/测试', modelId: 'kimi-k3', updatedAt: 0,
      messageCount: 2, pinned: false, archived: false
    },
    messages: [user, assistant]
  };
  const now = new Date(2026, 10, 8);
  const md = exporter.exportMarkdown(session, now);
  assert.match(md, /^# 导出\/测试/);
  assert.match(md, /## 用户/);
  assert.match(md, /## 助手/);
  assert.match(md, /工具：read_file/);
  assert.match(md, /````json/);
  assert.match(md, /> 思考过程/);
  assert.equal(exporter.exportFileName('a/b:c', now), 'a_b_c-2026-11-08.md');
  assert.equal(exporter.safeFileBase('   '), '对话');
});

test('session JSON export keeps parts and settles streaming flags', () => {
  const user = types.newChatMessage('u1', 'user', '你好');
  const assistant = types.newChatMessage('a1', 'assistant', '在');
  assistant.streaming = true;
  const call = types.toolCallPart('c1', 'read_file', '{"path":"a.txt"}');
  call.resultText = 'hi';
  call.status = types.TOOL_DONE;
  assistant.parts.push(call);
  const session = {
    meta: {
      id: 's1', title: 'JSON/导出', modelId: 'kimi-k3', updatedAt: 123,
      messageCount: 2, pinned: true, archived: false
    },
    messages: [user, assistant]
  };
  const now = new Date(2026, 10, 8, 12, 30);
  const parsed = JSON.parse(sessionExport.sessionExportJson(session, now));
  assert.equal(parsed.app, 'MinisHarmony');
  assert.equal(parsed.version, 1);
  assert.equal(parsed.session.meta.id, 's1');
  assert.equal(parsed.session.meta.pinned, true);
  assert.equal(parsed.session.messages.length, 2);
  assert.equal(parsed.session.messages[1].streaming, false);
  assert.equal(parsed.session.messages[1].parts[1].toolName, 'read_file');
  assert.equal(parsed.session.messages[1].parts[1].resultText, 'hi');
  // The source object is not mutated by the export.
  assert.equal(assistant.streaming, true);
  assert.equal(
    sessionExport.sessionJsonFileName('JSON/导出', now),
    'JSON_导出-2026-11-08.json'
  );
});

test('session JSON import validates the envelope and rebuilds parts', () => {
  const now = new Date(2026, 10, 8);
  const assistant = types.newChatMessage('a1', 'assistant', '在');
  const call = types.toolCallPart('c1', 'read_file', '{"path":"a.txt"}');
  call.resultText = 'hi';
  call.status = types.TOOL_DONE;
  assistant.parts.push(call);
  const original = {
    meta: {
      id: 's1', title: '标题', modelId: 'kimi-k3', updatedAt: 1,
      messageCount: 2, pinned: true, archived: true
    },
    messages: [types.newChatMessage('u1', 'user', '你好'), assistant]
  };
  const later = new Date(2026, 10, 9, 8, 0);
  const json = sessionExport.sessionExportJson(original, now);
  const imported = sessionExport.parseSessionExport(json, 'new-id', later);
  assert.equal(imported.ok, true);
  assert.equal(imported.session.meta.id, 'new-id');
  assert.equal(imported.session.meta.title, '标题（导入）');
  assert.equal(imported.session.meta.updatedAt, later.getTime());
  assert.equal(imported.session.meta.pinned, false);
  assert.equal(imported.session.meta.archived, false);
  assert.equal(imported.session.messages.length, 2);
  assert.equal(imported.session.messages[1].parts[1].toolName, 'read_file');
  assert.equal(imported.session.messages[1].parts[1].resultText, 'hi');

  const bad = JSON.parse(json);
  bad.app = 'Other';
  assert.equal(sessionExport.parseSessionExport(JSON.stringify(bad), 'n', later).ok, false);
  bad.app = 'MinisHarmony';
  bad.version = 99;
  assert.equal(sessionExport.parseSessionExport(JSON.stringify(bad), 'n', later).ok, false);
  assert.equal(sessionExport.parseSessionExport('{not json', 'n', later).ok, false);
  assert.equal(sessionExport.parseSessionExport('{}', 'n', later).ok, false);

  const pending = JSON.parse(json);
  pending.session.messages[1].parts[1].status = 'running';
  const recovered = sessionExport.parseSessionExport(
    JSON.stringify(pending), 'n', later
  );
  assert.equal(recovered.ok, true);
  const part = recovered.session.messages[1].parts[1];
  assert.equal(part.status, 'error');
  assert.equal(part.isError, true);
  // A partial result already written is kept; only an empty one gets a note.
  assert.equal(part.resultText, 'hi');
  pending.session.messages[1].parts[1].resultText = '';
  const noted = sessionExport.parseSessionExport(
    JSON.stringify(pending), 'n', later
  );
  assert.match(noted.session.messages[1].parts[1].resultText, /尚未完成/);
  // The exported source object keeps its original id and flags.
  assert.equal(original.meta.id, 's1');
  assert.equal(original.meta.pinned, true);
});

test('workspace listing sorts directories first and formats sizes', () => {
  const entries = [
    { name: 'b.txt', path: 'b.txt', isDir: false, size: 2048 },
    { name: 'Zeta', path: 'Zeta', isDir: true, size: 0 },
    { name: 'a.txt', path: 'a.txt', isDir: false, size: 10 },
    { name: 'alpha', path: 'alpha', isDir: true, size: 0 }
  ];
  const sorted = listing.sortFileEntries(entries);
  assert.deepEqual(sorted.map((e) => e.name), ['alpha', 'Zeta', 'a.txt', 'b.txt']);
  assert.deepEqual(entries.map((e) => e.name), ['b.txt', 'Zeta', 'a.txt', 'alpha']);
  assert.equal(listing.joinRelative('', 'a.txt'), 'a.txt');
  assert.equal(listing.joinRelative('src/core', 'x.ets'), 'src/core/x.ets');
  assert.equal(listing.parentRelative('src/core/x.ets'), 'src/core');
  assert.equal(listing.parentRelative('x.ets'), '');
  assert.equal(listing.formatFileSize(512), '512 B');
  assert.equal(listing.formatFileSize(2048), '2.0 KB');
  assert.equal(listing.formatFileSize(3 * 1024 * 1024), '3.0 MB');
});
