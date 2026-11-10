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
  // Every core module may call `t()`; rewrite that import unconditionally.
  for (const dep of deps.concat(['I18n'])) {
    source = source.split(`from './${dep}'`).join(`from './${dep}.mts'`);
  }
  // Node's type stripping erases annotations but keeps named imports, so
  // interfaces imported alongside runtime values would fail to link.
  if (name === 'PromptQueue') {
    source = source.replace(
      "import { ChatAttachment, MessagePart, filePart, imagePart, textPart } from './Types.mts';",
      "import { filePart, imagePart, textPart } from './Types.mts';");
  }
  if (name === 'SessionFolder') {
    source = source.replace(
      "import { MAX_SESSION_FOLDERS, SessionFolder, SessionMeta } from './Types.mts';",
      "import { MAX_SESSION_FOLDERS } from './Types.mts';");
  }
  if (name === 'SessionTitle') {
    source = source.replace(
      "import { ChatMessage, textOf } from './Types.mts';",
      "import { textOf } from './Types.mts';");
  }
  if (name === 'Mention') {
    source = source.replace("import { FileEntry } from './FileListing';\n", '');
  }
  writeFileSync(join(tmp, `${name}.mts`), source);
}

copyCore('I18n');
copyCore('SseParser');
copyCore('OpenCodeRules');
copyCore('Latex');
copyCore('Markdown', ['Latex']);
copyCore('SubagentJob');
copyCore('WebUrl');
copyCore('SubAgentRoster');
copyCore('Types');
copyCore('PromptQueue', ['Types', 'Paste']);
copyCore('SessionFolder', ['Types']);
copyCore('BrowserHistory');
copyCore('SessionTitle', ['Types']);
copyCore('Mention');
copyCore('UsageStats');
copyCore('McpOverrides');
copyCore('SyncMerge', ['Types']);
copyCore('ToolTypes');
copyCore('ToolCatalog', ['ToolTypes']);
copyCore('ToolProtocol', ['Types']);
copyCore('Workspace');
copyCore('MinisResource', ['Workspace']);
copyCore('Paste', ['MinisResource']);
copyCore('Terminal');
copyCore('SandboxProtocol');
copyCore('EventLog');
copyCore('EditPatch');
copyCore('Memory');
copyCore('MediaTime');
copyCore('MediaType');
copyCore('SessionStorage');
copyCore('ContextBudget', ['Types']);
copyCore('MarkdownExport', ['Types']);
copyCore('ShareCard', ['MarkdownExport']);
copyCore('Diagnostics', ['MarkdownExport', 'EventLog']);
copyCore('WebDav', ['BackupCrypto', 'Backup', 'SessionExport']);
copyCore('ScheduledTask');
copyCore('Device');
copyCore('OAuth');
copyCore('ToolArgs');
copyCore('ToolLoop');
copyCore('SessionExport', ['Types', 'MarkdownExport', 'McpOverrides']);
copyCore('FileListing');
copyCore('SessionParams', ['Types']);
copyCore('Appearance');
copyCore('Soul');
copyCore('SkillDoc');
copyCore('ModelCaps');
copyCore('ModelTest', ['I18n']);
copyCore('ConfigAudit', ['I18n']);
copyCore('ModelOverride');
copyCore('WidgetData');
copyCore('McpOAuth');
copyCore('McpProtocol', ['McpOAuth']);
copyCore('CodeHighlight');
copyCore('SharePayload');
copyCore('DeepLink');
copyCore('Types', ['ModelOverride', 'McpProtocol', 'SubAgentRoster']);
copyCore('Backup', ['Types', 'SessionExport', 'ModelOverride', 'McpProtocol', 'McpOAuth', 'SubAgentRoster']);
copyCore('BackupCrypto', ['Backup', 'SessionExport']);
copyCore('ImageGen', ['OpenCodeRules']);
copyCore('FastMode');
copyCore('AgentConfig', ['Types']);
copyCore('AnthropicProtocol', ['Types', 'ToolProtocol', 'ToolTypes', 'SseParser']);
copyCore('GeminiProtocol', ['Types', 'ToolProtocol', 'ToolTypes', 'SseParser']);
copyCore('ResponsesProtocol', ['Types', 'ToolProtocol', 'ToolTypes', 'SseParser']);

// ArkTS needs runtime imports for interface types; Node's type stripping
// needs them marked `type` (interfaces have no runtime binding).
function markTypeOnly(name, from, names) {
  const file = join(tmp, `${name}.mts`);
  let source = readFileSync(file, 'utf8');
  const plain = `import { ${names.join(', ')} } from './${from}.mts';`;
  const typed = `import type { ${names.join(', ')} } from './${from}.mts';`;
  if (source.indexOf(plain) >= 0) {
    writeFileSync(file, source.split(plain).join(typed));
    return;
  }
  // Multi-line imports: mark individual specifiers with inline `type`.
  const pattern = new RegExp(
    `import\\s*\\{([^}]*)\\}\\s*from\\s*'\\./${from}\\.mts';`);
  source = source.replace(pattern, (full, body) => {
    let updated = body;
    for (const typeName of names) {
      updated = updated.replace(
        new RegExp(`(^|[\\s,{])(${typeName})(?=\\s*[,}])`),
        `$1type $2`);
    }
    return `import {${updated}} from './${from}.mts';`;
  });
  writeFileSync(file, source);
}

markTypeOnly('AgentConfig', 'Types', ['AppSettings', 'ThinkingLevel']);
markTypeOnly('ToolCatalog', 'ToolTypes', ['ToolDefinition', 'ToolParameters', 'ToolProperty']);
markTypeOnly('ToolProtocol', 'Types', ['ChatMessage']);
markTypeOnly('SessionExport', 'Types', ['ChatMessage', 'MessagePart', 'StoredSession']);
markTypeOnly('SyncMerge', 'Types', ['StoredSession']);
markTypeOnly('SessionParams', 'Types', ['AppSettings', 'SessionMeta', 'ThinkingLevel']);
markTypeOnly('Types', 'ModelOverride', ['ModelOverride']);
markTypeOnly('Types', 'McpProtocol', ['McpServerConfig']);
markTypeOnly('Types', 'SubAgentRoster', ['SubAgentDefinition']);
markTypeOnly('Backup', 'Types', ['AppSettings', 'StoredSession']);
markTypeOnly('Backup', 'SessionExport', ['SessionBundleEnvelope']);
markTypeOnly('Backup', 'ModelOverride', ['ModelOverride']);
markTypeOnly('Backup', 'McpProtocol', ['McpServerConfig']);
markTypeOnly('Backup', 'McpOAuth', ['McpOAuthConfig']);
markTypeOnly('McpProtocol', 'McpOAuth', ['McpOAuthConfig']);
markTypeOnly('AnthropicProtocol', 'Types', ['ChatMessage']);
markTypeOnly('AnthropicProtocol', 'ToolProtocol', ['ImageResolver']);
markTypeOnly('AnthropicProtocol', 'ToolTypes', ['ToolDefinition']);
markTypeOnly('AnthropicProtocol', 'SseParser', ['DeltaResult', 'ToolCallDelta']);
markTypeOnly('GeminiProtocol', 'Types', ['ChatMessage']);
markTypeOnly('GeminiProtocol', 'ToolProtocol', ['ImageResolver']);
markTypeOnly('GeminiProtocol', 'ToolTypes', ['ToolDefinition']);
markTypeOnly('GeminiProtocol', 'SseParser', ['DeltaResult', 'ToolCallDelta']);
markTypeOnly('Markdown', 'Latex', ['GroupResult']);
markTypeOnly('ResponsesProtocol', 'ToolProtocol', ['ApiContentPart', 'ApiMessage', 'ApiToolCall']);
markTypeOnly('ResponsesProtocol', 'ToolTypes', ['ToolDefinition']);
markTypeOnly('ResponsesProtocol', 'SseParser', ['DeltaResult', 'TokenUsage', 'ToolCallDelta']);

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

const i18n = await import(pathToFileURL(join(tmp, 'I18n.mts')).href);
const sse = await import(pathToFileURL(join(tmp, 'SseParser.mts')).href);
const rules = await import(pathToFileURL(join(tmp, 'OpenCodeRules.mts')).href);
const md = await import(pathToFileURL(join(tmp, 'Markdown.mts')).href);
const types = await import(pathToFileURL(join(tmp, 'Types.mts')).href);
const promptQueue = await import(pathToFileURL(join(tmp, 'PromptQueue.mts')).href);
const folders = await import(pathToFileURL(join(tmp, 'SessionFolder.mts')).href);
const browserHistory = await import(pathToFileURL(join(tmp, 'BrowserHistory.mts')).href);
const sessionTitle = await import(pathToFileURL(join(tmp, 'SessionTitle.mts')).href);
const mention = await import(pathToFileURL(join(tmp, 'Mention.mts')).href);
const usageStats = await import(pathToFileURL(join(tmp, 'UsageStats.mts')).href);
const mcpOverrides = await import(pathToFileURL(join(tmp, 'McpOverrides.mts')).href);
const proto = await import(pathToFileURL(join(tmp, 'ToolProtocol.mts')).href);
const workspace = await import(pathToFileURL(join(tmp, 'Workspace.mts')).href);
const terminal = await import(pathToFileURL(join(tmp, 'Terminal.mts')).href);
const sandboxProtocol = await import(pathToFileURL(join(tmp, 'SandboxProtocol.mts')).href);
const log = await import(pathToFileURL(join(tmp, 'EventLog.mts')).href);
const edit = await import(pathToFileURL(join(tmp, 'EditPatch.mts')).href);
const catalog = await import(pathToFileURL(join(tmp, 'ToolCatalog.mts')).href);
const memory = await import(pathToFileURL(join(tmp, 'Memory.mts')).href);
const mediaTime = await import(pathToFileURL(join(tmp, 'MediaTime.mts')).href);
const mediaType = await import(pathToFileURL(join(tmp, 'MediaType.mts')).href);
const sessionStorage = await import(pathToFileURL(join(tmp, 'SessionStorage.mts')).href);
const agentConfig = await import(pathToFileURL(join(tmp, 'AgentConfig.mts')).href);
const budget = await import(pathToFileURL(join(tmp, 'ContextBudget.mts')).href);
const exporter = await import(pathToFileURL(join(tmp, 'MarkdownExport.mts')).href);
const toolArgs = await import(pathToFileURL(join(tmp, 'ToolArgs.mts')).href);
const toolLoop = await import(pathToFileURL(join(tmp, 'ToolLoop.mts')).href);
const sessionExport = await import(pathToFileURL(join(tmp, 'SessionExport.mts')).href);
const listing = await import(pathToFileURL(join(tmp, 'FileListing.mts')).href);
const sessionParams = await import(pathToFileURL(join(tmp, 'SessionParams.mts')).href);
const appearance = await import(pathToFileURL(join(tmp, 'Appearance.mts')).href);
const soul = await import(pathToFileURL(join(tmp, 'Soul.mts')).href);
const skilldoc = await import(pathToFileURL(join(tmp, 'SkillDoc.mts')).href);
const modelCaps = await import(pathToFileURL(join(tmp, 'ModelCaps.mts')).href);
const modelTest = await import(pathToFileURL(join(tmp, 'ModelTest.mts')).href);
const configAudit = await import(pathToFileURL(join(tmp, 'ConfigAudit.mts')).href);
const paste = await import(pathToFileURL(join(tmp, 'Paste.mts')).href);
const modelOverride = await import(pathToFileURL(join(tmp, 'ModelOverride.mts')).href);
const mcp = await import(pathToFileURL(join(tmp, 'McpProtocol.mts')).href);
const mcpOAuth = await import(pathToFileURL(join(tmp, 'McpOAuth.mts')).href);
const widgetData = await import(pathToFileURL(join(tmp, 'WidgetData.mts')).href);
const highlight = await import(pathToFileURL(join(tmp, 'CodeHighlight.mts')).href);
const share = await import(pathToFileURL(join(tmp, 'SharePayload.mts')).href);
const deepLink = await import(pathToFileURL(join(tmp, 'DeepLink.mts')).href);
const minisResource = await import(pathToFileURL(join(tmp, 'MinisResource.mts')).href);
const backup = await import(pathToFileURL(join(tmp, 'Backup.mts')).href);
const backupCrypto = await import(pathToFileURL(join(tmp, 'BackupCrypto.mts')).href);
const imageGen = await import(pathToFileURL(join(tmp, 'ImageGen.mts')).href);
const fastMode = await import(pathToFileURL(join(tmp, 'FastMode.mts')).href);
const anthropic = await import(pathToFileURL(join(tmp, 'AnthropicProtocol.mts')).href);
const gemini = await import(pathToFileURL(join(tmp, 'GeminiProtocol.mts')).href);
const responses = await import(pathToFileURL(join(tmp, 'ResponsesProtocol.mts')).href);
const latex = await import(pathToFileURL(join(tmp, 'Latex.mts')).href);
const jobs = await import(pathToFileURL(join(tmp, 'SubagentJob.mts')).href);
const webUrl = await import(pathToFileURL(join(tmp, 'WebUrl.mts')).href);
const shareCard = await import(pathToFileURL(join(tmp, 'ShareCard.mts')).href);
const diagnostics = await import(pathToFileURL(join(tmp, 'Diagnostics.mts')).href);
const webDav = await import(pathToFileURL(join(tmp, 'WebDav.mts')).href);
const scheduled = await import(pathToFileURL(join(tmp, 'ScheduledTask.mts')).href);
const device = await import(pathToFileURL(join(tmp, 'Device.mts')).href);
const syncMerge = await import(pathToFileURL(join(tmp, 'SyncMerge.mts')).href);
const roster = await import(pathToFileURL(join(tmp, 'SubAgentRoster.mts')).href);
const oauth = await import(pathToFileURL(join(tmp, 'OAuth.mts')).href);

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
  assert.equal(sse.parseErrorMessage('{"error":null,"message":"plain"}'), 'plain');
  assert.equal(sse.parseErrorMessage('{"error":{"message":"missing x-opencode-session"}}'), 'missing x-opencode-session');
  assert.equal(sse.parseErrorMessage('{"message":"plain"}'), 'plain');
  assert.equal(sse.parseErrorMessage('upstream exploded'), 'upstream exploded');
  assert.equal(sse.parseErrorMessage(''), '');
});

test('OpenAI null usage/choices fields do not crash the parser', () => {
  let delta = sse.parseOpenAiData('{"usage":null,"choices":[{"delta":{"content":"hi"}}]}');
  assert.equal(delta.content, 'hi');
  assert.equal(delta.usage.present, false);
  delta = sse.parseOpenAiData('{"usage":null,"choices":[]}');
  assert.equal(delta.usage.present, false);
  delta = sse.parseOpenAiData('{"choices":null,"usage":{"prompt_tokens":1}}');
  assert.equal(delta.usage.promptTokens, 1);
  assert.equal(delta.content, '');
  delta = sse.parseOpenAiData('{"choices":[null]}');
  assert.equal(delta.content, '');
  delta = sse.parseOpenAiData('{"choices":[{"delta":null}]}');
  assert.equal(delta.content, '');
  delta = sse.parseOpenAiData('{"error":null}');
  assert.equal(delta.error, '');
});

test('OpenAI null string fields never reach the UI as null', () => {
  // opencode.ai emits "content"/"reasoning": null on intermediate chunks;
  // assigning them crashed ChatApi.consumeEvent on delta.reasoning.length.
  let delta = sse.parseOpenAiData(
    '{"choices":[{"delta":{"content":null,"reasoning":null},"finish_reason":null}]}');
  assert.equal(delta.content, '');
  assert.equal(delta.reasoning, '');
  assert.equal(delta.finishReason, '');
  assert.equal(typeof delta.content, 'string');
  assert.equal(typeof delta.reasoning, 'string');
  delta = sse.parseOpenAiData('{"choices":[{"delta":{"reasoning_content":null}}]}');
  assert.equal(delta.reasoning, '');
  delta = sse.parseOpenAiData(
    '{"choices":[{"delta":{"tool_calls":[{"index":null,"id":null,' +
    '"function":{"name":null,"arguments":null}}]}}]}');
  assert.equal(delta.toolCalls.length, 1);
  assert.equal(delta.toolCalls[0].index, 0);
  assert.equal(delta.toolCalls[0].id, '');
  assert.equal(delta.toolCalls[0].name, '');
  assert.equal(delta.toolCalls[0].arguments, '');
  delta = sse.parseOpenAiData('{"error":{"message":null}}');
  assert.equal(typeof delta.error, 'string');
  assert.equal(delta.error.length > 0, true);
  assert.equal(sse.parseErrorMessage('{"error":{"message":null},"message":"plain"}'), 'plain');
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

test('Markdown standalone images parse with alt text and title', () => {
  const blocks = md.parseMarkdown([
    '![shot](minis://workspace/.minis-browser/shot-1.png)',
    '',
    '![alt](https://example.com/a.png "title")',
    '',
    'before ![inline](b.png) after'
  ].join('\n'));
  assert.equal(blocks[0].kind, md.MdBlockKind.Image);
  assert.equal(blocks[0].imageUrl, 'minis://workspace/.minis-browser/shot-1.png');
  assert.equal(blocks[0].imageAlt, 'shot');
  assert.equal(blocks[1].kind, md.MdBlockKind.Image);
  assert.equal(blocks[1].imageUrl, 'https://example.com/a.png');
  // Inline images stay in prose instead of swallowing surrounding text.
  assert.equal(blocks[2].kind, md.MdBlockKind.Paragraph);
  assert.equal(blocks[2].text, 'before ![inline](b.png) after');
});

test('Markdown tables parse header and rows', () => {
  const blocks = md.parseMarkdown('| A | B |\n|:--|--:|\n| 1 | 2 |\n| x | y |\n\nafter');
  assert.equal(blocks[0].kind, 'table');
  assert.deepEqual(blocks[0].rows, [['A', 'B'], ['1', '2'], ['x', 'y']]);
  assert.equal(blocks[1].kind, 'paragraph');
  const short = md.parseMarkdown('| H | I |\n|---|---|\n| only |\n\ntail');
  assert.deepEqual(short[0].rows, [['H', 'I'], ['only', '']]);
  const notTable = md.parseMarkdown('a | b\n---\ntext');
  assert.equal(notTable.some((b) => b.kind === 'table'), false);
});

test('Markdown inline parsing', () => {
  const parts = md.parseInline('a **b** and `c` and [d](https://x.y)');
  assert.equal(parts.some((p) => p.text === 'b' && p.bold), true);
  assert.equal(parts.some((p) => p.text === 'c' && p.code), true);
  assert.equal(parts.some((p) => p.text === 'd' && p.link === 'https://x.y'), true);
});

test('Markdown bare URLs keep punctuation and reject unsafe schemes', () => {
  const parts = md.parseInline('见 https://example.com/a?b=1。以及 http://x.y,');
  assert.deepEqual(
    parts.filter((p) => p.link.length > 0).map((p) => p.link),
    ['https://example.com/a?b=1', 'http://x.y']
  );
  assert.equal(parts.some((p) => p.text === '。以及 '), true);
  assert.equal(parts.some((p) => p.text === ','), true);
  assert.equal(md.isOpenableUrl('HTTPS://x.y'), true);
  assert.equal(md.isOpenableUrl('mailto:a@b.c'), true);
  assert.equal(md.isOpenableUrl('javascript:alert(1)'), false);
  assert.equal(md.isOpenableUrl('file:///etc/passwd'), false);
});

test('SKILL.md frontmatter and catalogue', () => {
  const doc = skilldoc.parseSkillDoc(
    '---\nname: "Deploy Helper"\ndescription: Build and deploy the HAP\n---\n\n# Steps\n\n1. build',
    skilldoc.skillIdFromFile('Deploy Helper.md')
  );
  assert.equal(doc.id, 'deploy-helper');
  assert.equal(doc.name, 'Deploy Helper');
  assert.equal(doc.description, 'Build and deploy the HAP');
  assert.equal(doc.body, '# Steps\n\n1. build');

  const plain = skilldoc.parseSkillDoc('Just do this', 'plain');
  assert.equal(plain.name, 'plain');
  assert.equal(plain.description, 'Just do this');
  assert.equal(plain.body, 'Just do this');

  assert.equal(skilldoc.skillIdFromFile('目录/My Skill.md'), 'my-skill');
  assert.equal(skilldoc.skillIdFromFile('!!!.md'), 'skill');

  const catalogue = skilldoc.skillCatalogue([doc]);
  assert.equal(catalogue.indexOf('Deploy Helper') >= 0, true);
  assert.equal(catalogue.indexOf('read_skill') >= 0, true);
  assert.equal(skilldoc.skillCatalogue([]), '');
  assert.equal(skilldoc.findSkill([doc], 'deploy-helper'), doc);
  assert.equal(skilldoc.findSkill([doc], 'Deploy Helper'), doc);
  assert.equal(skilldoc.findSkill([doc], 'nope'), null);
});

test('skill slash commands match enabled ids', () => {
  const ids = ['deploy-helper', 'review'];
  const bare = skilldoc.matchSkillCommand('/review', ids);
  assert.equal(bare.id, 'review');
  assert.equal(bare.rest, '');
  const withArgs = skilldoc.matchSkillCommand('  /Deploy-Helper 检查构建  ', ids);
  assert.equal(withArgs.id, 'deploy-helper');
  assert.equal(withArgs.rest, '检查构建');
  const tab = skilldoc.matchSkillCommand('/review\t这个 PR', ids);
  assert.equal(tab.rest, '这个 PR');
  assert.equal(skilldoc.matchSkillCommand('/unknown arg', ids), null);
  assert.equal(skilldoc.matchSkillCommand('/Deploy Helper', ['deploy-helper']), null);
  assert.equal(skilldoc.matchSkillCommand('review', ids), null);
  assert.equal(skilldoc.matchSkillCommand('/', ids), null);
});

test('model capability estimates and max token clamping', () => {
  const gpt = modelCaps.capsForModel('gpt-6-luna');
  assert.equal(gpt.contextWindow, 400000);
  assert.equal(gpt.vision, true);
  assert.equal(gpt.reasoning, true);
  assert.equal(modelCaps.capsForModel('Claude-Haiku-5-5').contextWindow, 200000);
  assert.equal(modelCaps.capsForModel('gemini-4-argon').contextWindow, 1000000);
  assert.equal(modelCaps.capsForModel('kimi-k2.7-code').vision, false);

  const unknown = modelCaps.capsForModel('my-custom-model');
  assert.equal(unknown.contextWindow, 128000);
  assert.equal(unknown.maxOutput, 8192);
  assert.equal(unknown.tools, true);

  assert.equal(modelCaps.clampMaxTokens(4096, gpt), 4096);
  assert.equal(modelCaps.clampMaxTokens(64000, gpt), 32768);
  assert.equal(modelCaps.clampMaxTokens(0, gpt), 32768);

  assert.equal(modelCaps.formatWindow(128000), '128k');
  assert.equal(modelCaps.formatWindow(1000000), '1m');
  assert.equal(modelCaps.contextPercent(64000, 128000), 50);
  assert.equal(modelCaps.contextPercent(200000, 128000), 100);
  assert.equal(modelCaps.contextPercent(0, 128000), 0);
  assert.equal(modelCaps.capsLabel(gpt).indexOf('视觉') >= 0, true);
});

test('session params merge over global settings', () => {
  const settings = types.defaultSettings();
  settings.modelId = 'global-model';
  settings.systemPrompt = 'base prompt';
  settings.thinkingLevel = 'medium';
  const meta = {
    id: 's1', title: 't', updatedAt: 0, modelId: '', messageCount: 0,
    pinned: false, archived: false
  };
  assert.equal(sessionParams.hasSessionOverride(meta), false);
  assert.equal(sessionParams.effectiveSettings(settings, meta).modelId, 'global-model');
  assert.equal(sessionParams.sessionParamSummary(meta), '');

  sessionParams.applySessionParams(meta, ' mini ', 'high', ' be brief ');
  assert.deepEqual(
    [meta.modelOverride, meta.thinkingOverride, meta.promptOverride],
    ['mini', 'high', 'be brief']
  );
  assert.equal(sessionParams.hasSessionOverride(meta), true);
  const eff = sessionParams.effectiveSettings(settings, meta);
  assert.equal(eff.modelId, 'mini');
  assert.equal(eff.thinkingLevel, 'high');
  assert.equal(eff.systemPrompt, 'base prompt\n\nbe brief');
  assert.equal(settings.modelId, 'global-model');
  assert.equal(sessionParams.sessionParamSummary(meta), 'mini · 思考 high · 追加指令');

  sessionParams.applySessionParams(meta, '', 'sometimes', '');
  assert.equal(meta.modelOverride, '');
  assert.equal(meta.thinkingOverride, '');
  assert.equal(sessionParams.effectiveSettings(settings, meta).thinkingLevel, 'medium');

  sessionParams.applySessionParams(meta, 'x', 'off', '');
  assert.equal(sessionParams.effectiveSettings(settings, meta).thinkingLevel, 'off');
  sessionParams.clearSessionParams(meta);
  assert.equal(sessionParams.hasSessionOverride(meta), false);
  assert.equal(sessionParams.effectiveSettings(settings, meta).modelId, 'global-model');
  assert.equal(sessionParams.effectiveSettings(settings, null).modelId, 'global-model');
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
  assert.equal(settings.appLockEnabled, false);
  assert.equal(types.cloneSettings({ ...settings, appLockEnabled: true }).appLockEnabled, true);
  assert.equal(settings.accentColor, types.DEFAULT_ACCENT_COLOR);
  assert.equal(settings.fontScale, 1);
  assert.equal(types.normalizeAccentColor('#abcdef'), '#abcdef');
  assert.equal(types.normalizeAccentColor('#GGGGGG'), types.DEFAULT_ACCENT_COLOR);
  assert.equal(types.normalizeAccentColor('red'), types.DEFAULT_ACCENT_COLOR);
  assert.equal(types.clampFontScale(0.5), 0.9);
  assert.equal(types.clampFontScale(2), 1.3);
  assert.equal(types.clampFontScale(Number.NaN), 1);
  assert.equal(types.scaleFont(10, 1.15), 12);
  assert.equal(types.normalizeSessionBadge('background'), 'background');
  assert.equal(types.normalizeSessionBadge('interrupted'), 'interrupted');
  assert.equal(types.normalizeSessionBadge('syncing'), 'syncing');
  assert.equal(types.normalizeSessionBadge('unknown'), '');
  assert.equal(types.normalizeSessionBadge(undefined), '');
  assert.equal(appearance.fontScaleLabel(0.9), '小');
  assert.equal(appearance.fontScaleLabel(1), '标准');
  assert.equal(appearance.fontScaleLabel(1.15), '大');
  assert.equal(appearance.fontScaleLabel(1.3), '特大');
  assert.equal(appearance.ACCENT_PRESETS.length, 6);
  assert.equal(types.normalizeAccentColor(appearance.ACCENT_PRESETS[3].value),
    appearance.ACCENT_PRESETS[3].value);
  assert.equal(settings.soulId, 'general');
  assert.equal(soul.normalizeSoulId('engineer'), 'engineer');
  assert.equal(soul.normalizeSoulId('nope'), 'general');
  assert.equal(soul.soulPrompt('general'), '');
  assert.equal(soul.soulPrompt('engineer').length > 0, true);
  assert.equal(soul.soulPrompt('unknown'), '');
  assert.equal(soul.soulPresets().length >= 5, true);
  assert.deepEqual(settings.enabledSkills, []);
  assert.deepEqual(
    types.cloneSettings({ ...settings, enabledSkills: ['a', 'a', ''] }).enabledSkills,
    ['a']
  );
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
  const scaled = types.cloneSettings({
    ...settings,
    fontScale: 1.2,
    messageFontScale: undefined,
    inputFontScale: undefined
  });
  assert.equal(scaled.messageFontScale, 1.2, 'legacy message scale follows fontScale');
  assert.equal(scaled.inputFontScale, 1.2);
  assert.equal(types.cloneSettings({ ...settings, autoExpandThinking: true }).autoExpandThinking, true);
  assert.equal(types.cloneSettings({ ...settings, autoTitleEnabled: false }).autoTitleEnabled, false);
  assert.equal(types.cloneSettings({ ...settings, autoFocusInput: false }).autoFocusInput, false);
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

test('duplicate tool call ids are made unique', () => {
  const assistant = types.newChatMessage('a9', 'assistant', '');
  const first = types.toolCallPart('call_dup', 'read_file', '{"path":"a"}');
  first.resultText = 'A';
  first.status = types.TOOL_DONE;
  const second = types.toolCallPart('call_dup', 'read_file', '{"path":"b"}');
  second.resultText = 'B';
  second.status = types.TOOL_DONE;
  assistant.parts.push(first, second);

  const api = proto.toApiMessages([assistant]);
  assert.equal(api[0].tool_calls[0].id, 'call_dup');
  assert.equal(api[0].tool_calls[1].id, 'call_dup_2');
  assert.equal(api[1].tool_call_id, 'call_dup');
  assert.equal(api[2].tool_call_id, 'call_dup_2');
  assert.equal(api[1].content, 'A');
  assert.equal(api[2].content, 'B');
});

test('tool calls without a name are not sent', () => {
  const assistant = types.newChatMessage('a10', 'assistant', 'thinking');
  assistant.parts.push(types.toolCallPart('call_blank', '   ', '{}'));
  assistant.parts.push(types.toolCallPart('call_ok', 'now', '{}'));
  const api = proto.toApiMessages([assistant]);
  assert.equal(api.length, 2);
  assert.equal(api[0].tool_calls.length, 1);
  assert.equal(api[0].tool_calls[0].id, 'call_ok');
});

test('user image parts become multimodal content', () => {
  const user = types.newChatMessage('u1', 'user', '看看这张图');
  user.parts.push(types.imagePart('attachment:a.png', 'image/png'));
  const api = proto.toApiMessages([user], (uri, mime) =>
    uri === 'attachment:a.png' ? 'data:image/png;base64,AAA' : '');
  assert.equal(api.length, 1);
  assert.equal(Array.isArray(api[0].content), true);
  assert.equal(api[0].content[0].type, 'text');
  assert.equal(api[0].content[0].text, '看看这张图');
  assert.equal(api[0].content[1].type, 'image_url');
  assert.equal(api[0].content[1].image_url.url, 'data:image/png;base64,AAA');

  const onlyImage = types.newChatMessage('u2', 'user', '');
  onlyImage.parts.push(types.imagePart('attachment:b.jpg', 'image/jpeg'));
  const api2 = proto.toApiMessages([onlyImage], () => 'data:image/jpeg;base64,BBB');
  assert.equal(api2.length, 1);
  assert.equal(api2[0].content.length, 1);
  assert.equal(api2[0].content[0].type, 'image_url');

  const unresolved = types.newChatMessage('u3', 'user', 'hi');
  unresolved.parts.push(types.imagePart('attachment:c.png', 'image/png'));
  const api3 = proto.toApiMessages([unresolved], () => '');
  assert.deepEqual(api3, [{ role: 'user', content: 'hi' }]);
});

test('file parts stay out of the payload but keep the text note', () => {
  const user = types.newChatMessage('u4', 'user', '[视频] a.mp4');
  user.parts.push(types.filePart('attachment:a.mp4', 'video/mp4'));
  const api = proto.toApiMessages([user], () => 'data:video/mp4;base64,XXX');
  assert.deepEqual(api, [{ role: 'user', content: '[视频] a.mp4' }]);
  const onlyFile = types.newChatMessage('u5', 'user', '');
  onlyFile.parts.push(types.filePart('attachment:b.mp4', 'video/mp4'));
  assert.deepEqual(proto.toApiMessages([onlyFile], () => 'x'), []);
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

test('context budget accepts 600k and 1M characters', () => {
  assert.equal(types.MIN_CONTEXT_BUDGET_CHARS, 4000);
  assert.equal(types.MAX_CONTEXT_BUDGET_CHARS, 2000000);
  assert.equal(types.clampContextBudget(60000), 60000);
  assert.equal(types.clampContextBudget(600000), 600000);
  assert.equal(types.clampContextBudget(1000000), 1000000);
  assert.equal(types.clampContextBudget(2000000), 2000000);
  assert.equal(types.clampContextBudget(2000001), 2000000);
  assert.equal(types.clampContextBudget(3999), 4000);
  assert.equal(types.clampContextBudget(12345.9), 12345);
  assert.equal(types.clampContextBudget(Number.NaN), 60000);
  const settings = types.defaultSettings();
  assert.equal(settings.contextBudgetChars, 60000);
  const restored = types.cloneSettings({ contextBudgetChars: 1000000 });
  assert.equal(restored.contextBudgetChars, 1000000);
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
  // newLogEvent stamps Date.now(), so assert the shape, not today's date.
  assert.match(viewed, /\d\d-\d\d \d\d:\d\d:\d\d model_done/);
  assert.match(viewed, /42ms/);
  assert.match(viewed, /req=ab12cd34/);
  assert.equal(log.formatEventLine('garbage'), 'garbage');
  assert.equal(log.formatEventLine('  '), '');
});

test('parsed event lines expose level and event for filtering', () => {
  const line = JSON.stringify({
    ts: 0,
    event: 'model_error',
    level: 'error',
    tool: '',
    ok: false,
    durationMs: 5,
    detail: 'boom',
    req: ''
  });
  const parsed = log.parseEventLine(line);
  assert.equal(parsed.level, 'error');
  assert.equal(parsed.event, 'model_error');
  assert.equal(parsed.ok, false);
  assert.equal(parsed.raw, line);
  const broken = log.parseEventLine('garbage');
  assert.equal(broken.level, 'info');
  assert.equal(broken.detail, 'garbage');

  const nulls = log.parseEventLine(JSON.stringify({
    ts: null,
    event: null,
    level: null,
    tool: null,
    detail: null,
    req: null
  }));
  assert.equal(nulls.event, '?');
  assert.equal(nulls.level, 'info');
  assert.equal(nulls.tool, '');
  assert.equal(nulls.detail, '');
  assert.equal(nulls.req, '');
  assert.equal(log.formatEventLine('{"event":null,"tool":null,"detail":null}').includes('✓'), true);
});

test('auto compaction percent clamps to the safe range', () => {
  assert.equal(types.clampAutoCompactPercent(NaN), 80);
  assert.equal(types.clampAutoCompactPercent(10), 50);
  assert.equal(types.clampAutoCompactPercent(99), 95);
  assert.equal(types.clampAutoCompactPercent(72.8), 72);
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

test('memory logs persist newest first and drop junk rows', () => {
  assert.deepEqual(memory.parseMemoryLogs(''), []);
  assert.deepEqual(memory.parseMemoryLogs('nope'), []);
  assert.deepEqual(memory.parseMemoryLogs('[{"at":0,"text":"x"}]'), []);
  const parsed = memory.parseMemoryLogs(JSON.stringify([
    { at: 3, text: '检索记忆：x' },
    { at: 2, text: '   ' },
    { at: 1, text: '保存记忆文件 GLOBAL.md' }
  ]));
  assert.deepEqual(parsed, [
    { at: 3, text: '检索记忆：x' },
    { at: 1, text: '保存记忆文件 GLOBAL.md' }
  ]);
  let logs = memory.mergeMemoryLog([], { at: 5, text: 'new' }, 2);
  logs = memory.mergeMemoryLog(logs, { at: 6, text: 'newer' }, 2);
  assert.deepEqual(logs.map((row) => row.text), ['newer', 'new']);
  logs = memory.mergeMemoryLog(logs, { at: 7, text: 'newest' }, 2);
  assert.deepEqual(logs.map((row) => row.text), ['newest', 'newer']);
  assert.deepEqual(memory.mergeMemoryLog([], { at: 1, text: 'a' }, 0).length, 1);
  assert.equal(JSON.parse(memory.memoryLogsJson(logs)).length, 2);
});

test('memory lines can be listed, rewritten and removed in place', () => {
  assert.deepEqual(memory.memoryLines('- one\n\n- two\r\n'), [
    { index: 0, text: '- one' },
    { index: 2, text: '- two' }
  ]);
  assert.deepEqual(memory.memoryLines('   \n\t\n'), []);
  assert.equal(memory.memoryLineAt('- one\n- two', 1), '- two');
  assert.equal(memory.memoryLineAt('- one', 4), '');
  assert.equal(
    memory.replaceMemoryLine('- one\n- two', 0, '  - fixed\nnext '),
    '- fixed next\n- two'
  );
  assert.equal(memory.replaceMemoryLine('- one', 3, 'x'), '- one');
  assert.equal(memory.removeMemoryLine('- one\n\n- two', 1), '- one\n- two');
  assert.equal(memory.removeMemoryLine('a\nb\n', 0), 'b\n');
  assert.equal(memory.removeMemoryLine('a', -1), 'a');
  assert.equal(memory.memoryLineAt('a\n\nb', 1), '');
});

test('audio clock labels handle missing and long positions', () => {
  assert.equal(mediaTime.mediaClock(0), '0:00');
  assert.equal(mediaTime.mediaClock(-500), '0:00');
  assert.equal(mediaTime.mediaClock(Number.NaN), '0:00');
  assert.equal(mediaTime.mediaClock(Number.POSITIVE_INFINITY), '0:00');
  assert.equal(mediaTime.mediaClock(5000), '0:05');
  assert.equal(mediaTime.mediaClock(61000), '1:01');
  assert.equal(mediaTime.mediaClock(3600000), '60:00');
});

test('media preview kind follows the file extension', () => {
  assert.equal(mediaType.mediaKindOf('clip.MP4'), 'video');
  assert.equal(mediaType.mediaKindOf('notes/voice.mp3'), 'audio');
  assert.equal(mediaType.mediaKindOf('cover.jpeg'), 'image');
  assert.equal(mediaType.mediaKindOf('README.md'), '');
  assert.equal(mediaType.mediaKindOf('no-extension'), '');
  assert.equal(mediaType.mediaKindOf('trailing.'), '');
});

test('session storage ledger validates paths and totals by session', () => {
  const raw = JSON.stringify([
    { sessionId: 'a', path: 'notes/a.md', bytes: 10, at: 1 },
    { sessionId: 'a', path: 'notes/a.md', bytes: 20, at: 2 },
    { sessionId: 'b', path: '../escape', bytes: 5, at: 3 },
    { sessionId: 'b', path: '/abs', bytes: 5, at: 3 },
    { sessionId: 'b', path: 'a\\b', bytes: 5, at: 3 },
    { sessionId: 'b', path: 'ok.txt', bytes: -1, at: 3 },
    { sessionId: 'b', path: 'ok.txt', bytes: 3, at: 0 },
    { sessionId: '', path: 'x', bytes: 1, at: 1 },
    { sessionId: 'b', path: 'ok.txt', bytes: 7, at: 4 }
  ]);
  const entries = sessionStorage.parseStorageEntries(raw);
  assert.deepEqual(entries, [
    { sessionId: 'a', path: 'notes/a.md', bytes: 20, at: 2 },
    { sessionId: 'b', path: 'ok.txt', bytes: 7, at: 4 }
  ]);
  assert.deepEqual(sessionStorage.parseStorageEntries('nope'), []);
  assert.deepEqual(sessionStorage.storagePaths(entries, 'a'), ['notes/a.md']);

  let merged = sessionStorage.mergeStorageEntry(entries, {
    sessionId: 'a', path: 'notes/a.md', bytes: 30, at: 5
  }, 10);
  assert.equal(merged.length, 2);
  assert.equal(merged[1].bytes, 30);
  merged = sessionStorage.mergeStorageEntry(merged, {
    sessionId: 'c', path: 'c.txt', bytes: 1, at: 6
  }, 2);
  assert.deepEqual(merged.map((row) => row.path), ['notes/a.md', 'c.txt']);

  const totals = sessionStorage.storageTotals(entries, [
    { sessionId: 'a', uri: 'att.png', bytes: 100 },
    { sessionId: 'a', uri: 'att.png', bytes: 100 },
    { sessionId: 'c', uri: 'voice.mp3', bytes: 5 }
  ]);
  assert.equal(totals[0].sessionId, 'a');
  assert.equal(totals[0].workspaceFiles, 1);
  assert.equal(totals[0].workspaceBytes, 20);
  assert.equal(totals[0].attachmentFiles, 1);
  assert.equal(totals[0].attachmentBytes, 100);
  const c = totals.find((row) => row.sessionId === 'c');
  assert.equal(c.attachmentFiles, 1);
  assert.equal(c.workspaceBytes, 0);
});

test('tool catalogue exposes file_edit with a safe schema', () => {
  const tools = catalog.builtinToolDefinitions();
  const owner = tools.find((tool) => tool.name === 'file_edit');
  assert.notEqual(owner, undefined);
  assert.deepEqual(owner.parameters.required, ['path', 'old_string', 'new_string']);
  assert.equal(owner.parameters.properties.replace_all.type, 'boolean');
  const subagent = tools.find((tool) => tool.name === 'subagent_task');
  assert.notEqual(subagent, undefined);
  // action defaults to delegate, so prompt is conditionally required.
  assert.deepEqual(subagent.parameters.required, []);
  assert.equal(subagent.parameters.properties.action.type, 'string');
  assert.equal(subagent.parameters.properties.job_id.type, 'string');
  assert.equal(subagent.parameters.properties.wait.type, 'boolean');
  assert.equal(subagent.parameters.properties.label.type, 'string');
  const imageTool = tools.find((tool) => tool.name === 'generate_image');
  assert.notEqual(imageTool, undefined);
  assert.deepEqual(imageTool.parameters.required, ['prompt']);
  assert.equal(imageTool.parameters.properties.size.type, 'string');
  const readClipboard = tools.find((tool) => tool.name === 'clipboard_read');
  assert.notEqual(readClipboard, undefined);
  assert.deepEqual(readClipboard.parameters.required, []);
  const writeClipboard = tools.find((tool) => tool.name === 'clipboard_write');
  assert.notEqual(writeClipboard, undefined);
  assert.deepEqual(writeClipboard.parameters.required, ['text']);
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

test('rerun from a tool call cuts at the block boundary only', () => {
  const user = types.newChatMessage('u', 'user', 'do it');
  const assistant = types.newChatMessage('a', 'assistant', '');
  const call1 = types.toolCallPart('t1', 'shell_execute', '{"command":"ls"}');
  call1.resultText = 'ok';
  call1.status = 'done';
  const call2 = types.toolCallPart('t2', 'read_file', '{"path":"x"}');
  assistant.parts = [types.textPart('plan'), call1, call2];
  const later = types.newChatMessage('u2', 'user', 'next');

  const cut = types.rerunCutFromTool([user, assistant, later], 'a', 't2');
  assert.equal(cut.length, 2);
  assert.deepEqual(cut.map((message) => message.id), ['u', 'a']);
  assert.deepEqual(cut[1].parts
    .filter((part) => part.kind === 'tool_call')
    .map((part) => part.toolCallId), ['t1']);
  assert.equal(cut[1].parts[0].text, 'plan');

  // First meaningful block: dropping the whole turn is equivalent.
  const only = types.newChatMessage('b', 'assistant', '');
  only.parts = [types.reasoningPart('hmm'), types.toolCallPart('t3', 'now', '{}')];
  assert.deepEqual(types.rerunCutFromTool([user, only], 'b', 't3')
    .map((message) => message.id), ['u']);

  // Missing message / non-tool part.
  assert.equal(types.rerunCutFromTool([user, assistant], 'a', 'nope'), null);
  assert.equal(types.rerunCutFromTool([user], 'u', 't1'), null);

  // A cut that would leave no history to send is rejected.
  const first = types.newChatMessage('c', 'assistant', '');
  first.parts = [types.toolCallPart('t4', 'now', '{}')];
  assert.equal(types.rerunCutFromTool([first], 'c', 't4'), null);

  // Imported parts without an id fall back to name + arguments.
  const host = types.newChatMessage('d', 'assistant', '');
  host.parts = [types.toolCallPart('', 'now', '{}')];
  assert.equal(types.toolPartKey(host.parts[0]), 'now:{}');
  assert.deepEqual(types.rerunCutFromTool([user, host], 'd', 'now:{}')
    .map((message) => message.id), ['u']);
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

test('multi-session bundle round-trips every session with fresh ids', () => {
  const now = new Date(2026, 10, 8, 9, 0);
  const makeSession = (id, title) => ({
    meta: {
      id, title, modelId: 'kimi-k3', updatedAt: 1,
      messageCount: 1, pinned: false, archived: false
    },
    messages: [types.newChatMessage('u-' + id, 'user', 'hi ' + id)]
  });
  const bundle = sessionExport.sessionBundleJson(
    [makeSession('a', 'First'), makeSession('b', 'Second')], now);
  const parsed = JSON.parse(bundle);
  assert.equal(parsed.app, 'MinisHarmony');
  assert.equal(parsed.sessions.length, 2);
  assert.equal(parsed.session, undefined);
  assert.equal(sessionExport.sessionBundleFileName(now), 'minis-sessions-2026-11-08.json');

  let counter = 0;
  const imported = sessionExport.parseSessionsExport(bundle, () => 'n' + (++counter), now);
  assert.equal(imported.ok, true);
  assert.equal(imported.sessions.length, 2);
  assert.equal(imported.sessions[0].meta.id, 'n1');
  assert.equal(imported.sessions[1].meta.id, 'n2');
  assert.equal(imported.sessions[0].meta.title, 'First（导入）');

  // A single-session export is accepted by the same importer.
  const single = sessionExport.parseSessionsExport(
    sessionExport.sessionExportJson(makeSession('c', 'Solo'), now),
    () => 'one', now);
  assert.equal(single.ok, true);
  assert.equal(single.sessions.length, 1);
  assert.equal(single.sessions[0].meta.id, 'one');

  const empty = sessionExport.parseSessionsExport(
    JSON.stringify({ app: 'MinisHarmony', version: 1, sessions: [] }), () => 'x', now);
  assert.equal(empty.ok, false);
});

test('model overrides match by exact id and normalize numeric fields', () => {
  const list = modelOverride.normalizeModelOverrides([
    { modelId: ' kimi-k3 ', temperature: 0.3, topP: 0.9, maxTokens: 4096.7,
      extraHeaders: '{"X-Title":"Minis"}', extraBody: '{"provider":{}}' },
    { modelId: 'kimi-k3', temperature: 1.5, topP: 1, maxTokens: 1,
      extraHeaders: '', extraBody: '' },
    { modelId: '', temperature: 1, topP: 1, maxTokens: 1, extraHeaders: '', extraBody: '' },
    { modelId: 'claude-x', temperature: -1, topP: -1, maxTokens: 0,
      extraHeaders: '', extraBody: '' }
  ]);
  assert.equal(list.length, 2);
  assert.equal(list[0].modelId, 'kimi-k3');
  assert.equal(list[0].temperature, 0.3);
  assert.equal(list[0].maxTokens, 4096);
  assert.equal(list[1].temperature, -1);
  assert.equal(modelOverride.findModelOverride(list, 'kimi-k3').maxTokens, 4096);
  assert.equal(modelOverride.findModelOverride(list, 'Kimi-K3'), null);
  assert.equal(modelOverride.findModelOverride(list, ''), null);
  assert.equal(modelOverride.overrideSummary(list[1]), '未设置覆盖项');
});

test('extra headers and extra body validate and merge safely', () => {
  assert.deepEqual(modelOverride.parseExtraHeaders(''), {});
  assert.deepEqual(modelOverride.parseExtraHeaders(' {"X-A":"1"} '), { 'X-A': '1' });
  assert.equal(modelOverride.parseExtraHeaders('{"X-A":1}'), null);
  assert.equal(modelOverride.parseExtraHeaders('[]'), null);
  assert.equal(modelOverride.parseExtraHeaders('{'), null);

  assert.deepEqual(modelOverride.parseExtraBody(''), {});
  assert.equal(modelOverride.parseExtraBody('[1]'), null);
  assert.equal(modelOverride.parseExtraBody('nope'), null);

  const headers = modelOverride.mergeExtraHeaders(
    { 'Content-Type': 'application/json', 'X-B': 'old' },
    '{"X-B":"new","X-C":"3"}');
  assert.deepEqual(headers, {
    'Content-Type': 'application/json', 'X-B': 'new', 'X-C': '3'
  });

  const base = JSON.stringify({ model: 'm', temperature: 1, top_p: 0.5, tools: [] });
  const merged = JSON.parse(modelOverride.applyExtraBody(base, '{"top_p":0.2,"seed":7}'));
  assert.equal(merged.model, 'm');
  assert.equal(merged.top_p, 0.2);
  assert.equal(merged.seed, 7);
  assert.equal(modelOverride.applyExtraBody(base, 'not json'), base);
  assert.equal(modelOverride.applyExtraBody(base, ''), base);
});

test('MCP names, requests and SSE replies are normalized', () => {
  assert.equal(mcp.exposedToolName('Search Box', 'web.search'), 'mcp_search_box_web_search');
  assert.equal(mcp.exposedToolName('a/b', 'x.y'), 'mcp_a_b_x_y');
  const longName = mcp.exposedToolName('server', 'x'.repeat(80));
  assert.equal(longName.length, 64);
  assert.match(longName, /^[A-Za-z0-9_-]+$/);

  const request = JSON.parse(mcp.rpcRequest(3, 'tools/list', ''));
  assert.equal(request.jsonrpc, '2.0');
  assert.equal(request.id, 3);
  assert.equal(request.method, 'tools/list');
  assert.deepEqual(request.params, {});
  const notification = JSON.parse(mcp.rpcNotification('notifications/initialized', ''));
  assert.equal(notification.id, undefined);
  assert.equal(notification.method, 'notifications/initialized');

  const plain = mcp.parseRpcBody('{"jsonrpc":"2.0","id":2,"result":{"ok":1}}', 2);
  assert.equal(plain.result.ok, 1);
  const sse = [
    'event: message',
    'data: {"jsonrpc":"2.0","method":"notifications/message","params":{}}',
    '',
    'data: {"jsonrpc":"2.0","id":2,"result":{"ok":2}}',
    ''
  ].join('\n');
  assert.equal(mcp.parseRpcBody(sse, 2).result.ok, 2);
  assert.equal(mcp.parseRpcBody('not json', 1), null);
  const err = mcp.parseRpcBody(
    '{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"Method not found"}}', 1);
  assert.equal(mcp.rpcErrorMessage(err), 'MCP 错误 (-32601)：Method not found');
});

test('MCP tool lists and call results flatten into model-friendly text', () => {
  const tools = mcp.toolsFromResult('srv', 'Search', JSON.stringify({
    tools: [
      {
        name: 'query',
        description: 'Run a query',
        inputSchema: {
          type: 'object',
          properties: { q: { type: 'string' }, limit: { type: 'number' } },
          required: ['q']
        }
      },
      { name: '' },
      { description: 'missing name' }
    ]
  }));
  assert.equal(tools.length, 1);
  assert.equal(tools[0].exposedName, 'mcp_srv_query');
  assert.equal(tools[0].serverName, 'Search');
  const schema = JSON.parse(tools[0].schemaJson);
  assert.deepEqual(schema.required, ['q']);
  assert.equal(schema.properties.q.type, 'string');
  assert.deepEqual(mcp.toolsFromResult('s', 'S', 'bad json'), []);

  const text = mcp.callResultText(JSON.stringify({
    content: [
      { type: 'text', text: 'first' },
      { type: 'image', text: '' },
      { type: 'text', text: 'second' }
    ],
    isError: false
  }));
  assert.equal(text, 'first\n[image 内容未展开]\nsecond');
  assert.equal(mcp.isCallError('{"isError":true}'), true);
  assert.equal(mcp.isCallError('{"isError":false}'), false);

  const servers = mcp.normalizeMcpServers([
    { id: 'a', name: ' A ', url: ' https://x/mcp ', headers: '', enabled: true },
    { id: 'b', name: '', url: 'ftp://nope', headers: '', enabled: true },
    { id: 'a', name: 'dup', url: 'https://y/mcp', headers: '', enabled: false }
  ]);
  assert.equal(servers.length, 1);
  assert.equal(servers[0].url, 'https://x/mcp');
  assert.equal(servers[0].name, 'A');
});

test('MCP servers keep a normalized OAuth block', () => {
  const servers = mcp.normalizeMcpServers([{
    id: 's', name: 'S', url: 'https://x/mcp', headers: '', enabled: true,
    oauth: {
      mode: 'static', clientId: ' cid ', authorizationEndpoint: 'https://a/authorize',
      tokenEndpoint: 'https://a/token', scopes: '', redirectUri: '', resource: '',
      clientSecretSet: true
    }
  }]);
  assert.equal(servers[0].oauth.clientId, 'cid');
  assert.equal(servers[0].oauth.clientSecretSet, true);
  // Settings written before this feature have no oauth block at all.
  const legacy = mcp.normalizeMcpServers([{
    id: 'l', name: 'L', url: 'https://x/mcp', headers: '', enabled: true
  }]);
  assert.equal(mcpOAuth.isMcpOAuthConfigured(legacy[0].oauth), false);
});

test('MCP OAuth canonicalizes the RFC 8707 resource identifier', () => {
  assert.equal(mcpOAuth.canonicalResourceUri('https://mcp.example.com/api/'),
    'https://mcp.example.com/api');
  assert.equal(mcpOAuth.canonicalResourceUri('https://mcp.example.com/#frag'),
    'https://mcp.example.com');
  assert.equal(mcpOAuth.canonicalResourceUri('  https://mcp.example.com/v1  '),
    'https://mcp.example.com/v1');
  assert.equal(mcpOAuth.canonicalResourceUri(''), '');
  assert.equal(mcpOAuth.canonicalResourceUri('/just/a/path'), '');
  assert.equal(mcpOAuth.canonicalResourceUri('not a uri'), '');
  assert.equal(mcpOAuth.canonicalResourceUri('https:///path'), '');
});

test('MCP OAuth authorization URL carries PKCE and refresh hints', () => {
  const url = mcpOAuth.buildMcpAuthorizeUrl(
    'https://auth.example.com/authorize', 'client-42',
    'http://127.0.0.1:54546/callback', 'CHAL', 'STATE123',
    'https://mcp.example.com', 'openid email');
  assert.ok(url.startsWith('https://auth.example.com/authorize?'));
  assert.ok(url.includes('response_type=code'));
  assert.ok(url.includes('client_id=client-42'));
  assert.ok(url.includes('code_challenge=CHAL'));
  assert.ok(url.includes('code_challenge_method=S256'));
  assert.ok(url.includes('state=STATE123'));
  assert.ok(url.includes('access_type=offline'));
  assert.ok(url.includes('prompt=consent'));
  assert.ok(url.includes('resource=https%3A%2F%2Fmcp.example.com'));
  assert.ok(url.includes('scope=openid%20email'));
  assert.ok(url.includes('redirect_uri=http%3A%2F%2F127.0.0.1%3A54546%2Fcallback'));
  const reused = mcpOAuth.buildMcpAuthorizeUrl(
    'https://auth.example.com/authorize?audience=x', 'c',
    'http://127.0.0.1:54546/callback', 'CH', 'S', '', '');
  assert.ok(reused.includes('authorize?audience=x&'));
  assert.ok(!reused.includes('resource='));
  assert.ok(!reused.includes('scope='));
});

test('MCP OAuth token bodies include secret and resource only when set', () => {
  const plain = mcpOAuth.mcpTokenExchangeBody(
    'c d', 'http://localhost:54546/callback', 'cid', 'ver', '', '');
  assert.equal(plain, 'grant_type=authorization_code&code=c%20d' +
    '&redirect_uri=http%3A%2F%2Flocalhost%3A54546%2Fcallback' +
    '&client_id=cid&code_verifier=ver');
  const full = mcpOAuth.mcpTokenExchangeBody(
    'code', 'r', 'cid', 'ver', 'sekret', 'https://mcp.example.com');
  assert.ok(full.includes('client_secret=sekret'));
  assert.ok(full.includes('resource=https%3A%2F%2Fmcp.example.com'));
  const refresh = mcpOAuth.mcpRefreshBody(
    'r t', 'cid', '', 'https://mcp.example.com');
  assert.equal(refresh, 'grant_type=refresh_token&refresh_token=r%20t' +
    '&client_id=cid&resource=https%3A%2F%2Fmcp.example.com');
});

test('widget snapshots clamp, flatten and survive corrupt input', () => {
  assert.equal(widgetData.widgetExcerpt('  a\n\nb\t c  ', 20), 'a b c');
  assert.equal(widgetData.widgetExcerpt('x'.repeat(30), 10), 'xxxxxxxxxx…');
  const fallback = widgetData.defaultWidgetSnapshot();
  assert.equal(fallback.title, 'Minis');
  assert.equal(widgetData.parseWidgetSnapshot(''), null);
  assert.equal(widgetData.parseWidgetSnapshot('not json'), null);
  const parsed = widgetData.parseWidgetSnapshot(
    widgetData.widgetSnapshotJson({ title: '', body: 'hi', hint: '生成中', updatedAt: 5 }));
  assert.equal(parsed.title, 'Minis');
  assert.equal(parsed.body, 'hi');
  assert.equal(parsed.hint, '生成中');
  assert.equal(parsed.updatedAt, 5);
});

test('MCP OAuth config normalization and defaults', () => {
  const empty = mcpOAuth.normalizeMcpOAuth(undefined);
  assert.equal(mcpOAuth.isMcpOAuthConfigured(empty), false);
  const cfg = mcpOAuth.normalizeMcpOAuth({
    mode: 'dynamic', clientId: ' cid ', authorizationEndpoint: ' https://a/authorize ',
    tokenEndpoint: ' https://a/token ', scopes: ' openid ',
    redirectUri: '', resource: '', clientSecretSet: false
  });
  assert.equal(cfg.mode, 'static');
  assert.equal(cfg.clientId, 'cid');
  assert.equal(cfg.scopes, 'openid');
  assert.equal(mcpOAuth.isMcpOAuthConfigured(cfg), true);
  assert.equal(mcpOAuth.effectiveRedirectUri(cfg),
    'http://localhost:54546/callback');
  assert.equal(mcpOAuth.effectiveResource(cfg, 'https://mcp.example.com/mcp/'),
    'https://mcp.example.com/mcp');
  const override = mcpOAuth.normalizeMcpOAuth({
    mode: 'static', clientId: 'c', authorizationEndpoint: 'a', tokenEndpoint: 't',
    scopes: '', redirectUri: '', resource: ' https://res.example.com/ ',
    clientSecretSet: true
  });
  assert.equal(mcpOAuth.effectiveResource(override, 'https://mcp.example.com'),
    'https://res.example.com');
});

test('whole-library backup strips secrets and restores non-secret settings', () => {
  const now = new Date(2026, 10, 8, 15, 0);
  const settings = types.defaultSettings();
  settings.apiKey = 'sk-secret';
  settings.sandboxToken = 'sandbox-secret';
  settings.mcpServers = [{
    id: 'srv', name: 'Search', url: 'https://mcp.example/x',
    headers: '{"Authorization":"Bearer abc"}', enabled: true
  }];
  settings.modelOverrides = [{
    modelId: 'kimi-k3', temperature: 0.4, topP: 0.9, maxTokens: 0,
    extraHeaders: '{"X-Key":"secret"}', extraBody: '{"seed":1}'
  }];
  settings.temperature = 0.7;
  settings.fallbackModels = ['backup-a', 'backup-b'];
  const session = {
    meta: {
      id: 's1', title: 'T', modelId: 'kimi-k3', updatedAt: 1,
      messageCount: 1, pinned: false, archived: false
    },
    messages: [types.newChatMessage('m1', 'user', 'hi')]
  };
  const text = backup.backupJson(settings, [session], now);
  assert.ok(text.indexOf('sk-secret') < 0);
  assert.ok(text.indexOf('sandbox-secret') < 0);
  assert.ok(text.indexOf('Bearer abc') < 0);
  assert.ok(text.indexOf('secret') < 0);
  assert.equal(backup.backupFileName(now), 'minis-backup-2026-11-08.json');

  const restored = backup.parseBackupSettings(text);
  assert.notEqual(restored, null);
  assert.equal(restored.temperature, 0.7);
  assert.deepEqual(restored.fallbackModels, ['backup-a', 'backup-b']);
  assert.equal(restored.mcpServers.length, 1);
  assert.equal(restored.mcpServers[0].headers, '');
  assert.equal(restored.modelOverrides[0].temperature, 0.4);
  assert.equal(restored.modelOverrides[0].extraHeaders, '');
  assert.equal(restored.apiKey, '');

  const current = types.defaultSettings();
  current.apiKey = 'current-key';
  current.sandboxToken = 'current-token';
  const merged = backup.mergeBackupSettings(current, restored);
  assert.equal(merged.apiKey, 'current-key');
  assert.equal(merged.sandboxToken, 'current-token');
  assert.equal(merged.temperature, 0.7);

  // The same file is still accepted by the session importer.
  const imported = sessionExport.parseSessionsExport(text, () => 'new-id', now);
  assert.equal(imported.ok, true);
  assert.equal(imported.sessions.length, 1);
  assert.equal(imported.sessions[0].meta.id, 'new-id');

  assert.equal(backup.parseBackupSettings('{"app":"MinisHarmony"}'), null);
  assert.equal(backup.parseBackupSettings('not json'), null);
});

test('encrypted backup envelope validates shape and rejects tampering', () => {
  const envelope = backupCrypto.buildEncryptedEnvelope(
    '2026-11-08T00:00:00.000Z', '2026-11-08 08:00',
    'AAAAAAAAAAAAAAAAAAAAAA==', 'AAAAAAAAAAAAAAAA',
    'AAAAAAAAAAAAAAAAAAAAAAA=');
  const text = JSON.stringify(envelope);
  assert.equal(backupCrypto.isEncryptedBackup(text), true);
  const parsed = backupCrypto.parseEncryptedBackup(text);
  assert.equal(parsed.kdf, 'PBKDF2-HMAC-SHA256');
  assert.equal(parsed.cipher, 'AES-256-GCM');
  assert.equal(parsed.iterations, 120000);
  assert.equal(parsed.salt, 'AAAAAAAAAAAAAAAAAAAAAA==');

  assert.equal(backupCrypto.encryptedBackupFileName(new Date(2026, 10, 8)),
    'minis-backup-2026-11-08-enc.json');
  assert.equal(backupCrypto.encryptedBackupFileName(new Date(2026, 0, 2)),
    'minis-backup-2026-01-02-enc.json');
  assert.equal(backupCrypto.isEncryptedBackup('{"app":"MinisHarmony"}'), false);
  assert.equal(backupCrypto.isEncryptedBackup('not json'), false);

  assert.equal(backupCrypto.parseEncryptedBackup(JSON.stringify(
    { ...envelope, kind: 'backup' })), null);
  assert.equal(backupCrypto.parseEncryptedBackup(JSON.stringify(
    { ...envelope, kdf: 'none' })), null);
  assert.equal(backupCrypto.parseEncryptedBackup(JSON.stringify(
    { ...envelope, iterations: 100 })), null);
  assert.equal(backupCrypto.parseEncryptedBackup(JSON.stringify(
    { ...envelope, iterations: 2000000 })), null);
  assert.equal(backupCrypto.parseEncryptedBackup(JSON.stringify(
    { ...envelope, payload: 'not base64!' })), null);
  assert.equal(backupCrypto.parseEncryptedBackup(JSON.stringify(
    { ...envelope, payload: 'AAAA' })), null);
});

test('fast mode only targets providers that accept service_tier', () => {
  assert.equal(fastMode.hostOf('https://API.x.ai:443/v1/chat'), 'api.x.ai');
  assert.equal(fastMode.hostOf('api.example.com/v1'), 'api.example.com');
  assert.equal(fastMode.hostOf('  '), '');
  assert.equal(fastMode.supportsFastMode('codex', ''), true);
  assert.equal(fastMode.supportsFastMode('custom', 'https://api.x.ai/v1'), true);
  assert.equal(fastMode.supportsFastMode('custom', 'https://relay.example.com/v1'), false);
  assert.equal(fastMode.supportsFastMode('opencode', 'https://api.x.ai/v1'), false);
  assert.equal(fastMode.serviceTierFor(true, 'codex', ''), 'priority');
  assert.equal(fastMode.serviceTierFor(true, 'custom', 'https://api.x.ai/v1'), 'priority');
  assert.equal(fastMode.serviceTierFor(true, 'opencode', ''), '');
  assert.equal(fastMode.serviceTierFor(false, 'codex', ''), '');
});

test('model fallback lists parse, trim and de-duplicate', () => {
  assert.deepEqual(types.parseModelList(' a, b\nb；c ,, '), ['a', 'b', 'c']);
  assert.deepEqual(types.parseModelList(''), []);
  assert.deepEqual(types.modelChain('m', []), ['m']);
  assert.deepEqual(types.modelChain('m', [' n ', 'm', 'n', '']), ['m', 'n']);
  assert.deepEqual(types.modelChain('  ', ['x']), ['x']);
  assert.deepEqual(types.modelChain('', []), []);
});

test('image generation builds compatible requests and parses responses', () => {
  assert.equal(imageGen.imageGenEndpoint('https://api.example.com/v1/'),
    'https://api.example.com/v1/images/generations');
  assert.equal(imageGen.imageGenEndpoint('api.example.com/v1'),
    'https://api.example.com/v1/images/generations');
  assert.equal(imageGen.imageGenEndpoint(''), '');
  assert.equal(imageGen.normalizeImageSize('1792x1024'), '1792x1024');
  assert.equal(imageGen.normalizeImageSize('512x512'), '1024x1024');
  assert.equal(imageGen.supportsImageGen('opencode'), true);
  assert.equal(imageGen.supportsImageGen('custom'), true);
  assert.equal(imageGen.supportsImageGen('anthropic'), false);
  assert.equal(imageGen.supportsImageGen('gemini'), false);
  const body = JSON.parse(imageGen.buildImageGenBody('img-1', 'a "cat"', 'bad'));
  assert.equal(body.model, 'img-1');
  assert.equal(body.prompt, 'a "cat"');
  assert.equal(body.size, '1024x1024');
  assert.equal(body.response_format, 'b64_json');

  assert.equal(imageGen.parseImageGenResponse('{"data":[{"b64_json":"QUJD"}]}').b64, 'QUJD');
  assert.equal(imageGen.parseImageGenResponse('{"data":[{"url":"https://x.test/a.png"}]}').url,
    'https://x.test/a.png');
  assert.equal(imageGen.parseImageGenResponse('{"data":[{"url":"file:///x"}]}').error.length > 0,
    true);
  assert.equal(imageGen.parseImageGenResponse('{"error":{"message":"nope"}}').error, 'nope');
  assert.equal(imageGen.parseImageGenResponse('nope').error.length > 0, true);
  assert.equal(imageGen.parseImageGenResponse('{"data":[]}').error.length > 0, true);

  assert.equal(imageGen.detectImageExtension(new Uint8Array([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0])), 'png');
  assert.equal(imageGen.detectImageExtension(new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0])), 'jpg');
  assert.equal(imageGen.detectImageExtension(new Uint8Array(
    [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50])), 'webp');
  assert.equal(imageGen.detectImageExtension(new Uint8Array([0x47, 0x49, 0x46, 0x38])), 'gif');
  assert.equal(imageGen.detectImageExtension(new Uint8Array([1, 2, 3])), '');
});

test('code highlighting segments cover the source without losing characters', () => {
  const js = 'const x = run(42); // note\nlet s = "hi";';
  const segments = highlight.highlightCode(js, 'ts');
  assert.equal(segments.map((s) => s.text).join(''), js);
  assert.ok(segments.some((s) => s.text === 'const' && s.kind === 'keyword'));
  assert.ok(segments.some((s) => s.text === 'run' && s.kind === 'function'));
  assert.ok(segments.some((s) => s.text === '42' && s.kind === 'number'));
  assert.ok(segments.some((s) => s.text === '"hi"' && s.kind === 'string'));
  assert.ok(segments.some((s) => s.kind === 'comment' && s.text.indexOf('// note') === 0));

  const py = 'def f(x):\n    # comment\n    return None';
  const pySegments = highlight.highlightCode(py, 'python');
  assert.equal(pySegments.map((s) => s.text).join(''), py);
  assert.ok(pySegments.some((s) => s.text === 'def' && s.kind === 'keyword'));
  assert.ok(pySegments.some((s) => s.text === 'None' && s.kind === 'keyword'));
  assert.ok(pySegments.some((s) => s.kind === 'comment'));

  const block = 'a /* one\n two */ b';
  const blockSegments = highlight.highlightCode(block, 'js');
  assert.equal(blockSegments.map((s) => s.text).join(''), block);
  assert.ok(blockSegments.some((s) => s.text === '/* one\n two */' && s.kind === 'comment'));

  const plain = highlight.highlightCode('text here', 'unknown-lang');
  assert.deepEqual(plain, [{ text: 'text here', kind: 'plain' }]);
  assert.deepEqual(highlight.highlightCode('', 'js'), [{ text: '', kind: 'plain' }]);
});

test('shared want payloads pick text and stream URIs defensively', () => {
  const text = share.sharedFromWant(
    { 'ability.params.content': '  hello  ', 'ability.params.stream': ['file://a', 3, 'file://b'] },
    '', 'text/plain');
  assert.equal(text.text, 'hello');
  assert.deepEqual(text.uris, ['file://a', 'file://b']);

  const legacy = share.sharedFromWant(
    { 'ohos.extra.param.key.content': 'older key' }, '', '');
  assert.equal(legacy.text, 'older key');

  const uriOnly = share.sharedFromWant(undefined, 'file://note.txt', 'text/plain');
  assert.equal(uriOnly.text, 'file://note.txt');
  const binaryUri = share.sharedFromWant(undefined, 'file://photo.jpg', 'image/jpeg');
  assert.equal(binaryUri.text, '');

  assert.equal(share.sharedFromWant(undefined, '', '').text, '');
  assert.equal(share.isTextualShare('text/markdown'), true);
  assert.equal(share.isTextualShare('application/json'), true);
  assert.equal(share.isTextualShare('image/png'), false);

  assert.deepEqual(
    share.imageUrisFromShare(undefined, 'file://photo.png', 'image/png'),
    ['file://photo.png']);
  assert.deepEqual(
    share.imageUrisFromShare(
      { 'ability.params.stream': ['file://a.jpg', 'file://note.txt', 'file://a.jpg'] },
      '', 'image/jpeg'),
    ['file://a.jpg', 'file://note.txt']);
  assert.deepEqual(
    share.imageUrisFromShare(undefined, 'file://doc.pdf', 'application/pdf'), []);
  assert.equal(
    share.imageUrisFromShare(undefined, 'file://x.png', 'image/png').length, 1);
});

test('minis deep links resolve sessions, resources and settings', () => {
  assert.deepEqual(deepLink.parseDeepLink('minis://session/abc-123'),
    { kind: 'session', value: 'abc-123' });
  assert.deepEqual(deepLink.parseDeepLink('MINIS://Chat/xyz?x=1#top'),
    { kind: 'session', value: 'xyz' });
  assert.deepEqual(deepLink.parseDeepLink('minis://s/id'),
    { kind: 'session', value: 'id' });
  assert.deepEqual(deepLink.parseDeepLink('minis://sessions/id'),
    { kind: 'session', value: 'id' });
  assert.deepEqual(deepLink.parseDeepLink('minis://session/id/browser/a%20b.html'),
    { kind: 'session', value: 'id', path: 'browser/a b.html' });
  assert.deepEqual(deepLink.parseDeepLink('minis://open?session=id&path=%2Fbrowser%2Fx.html'),
    { kind: 'session', value: 'id', path: '/browser/x.html' });
  assert.deepEqual(deepLink.parseDeepLink('minis://open?path=%2Fworkspace%2Fa.md'),
    { kind: 'resource', value: '', path: '/workspace/a.md' });
  assert.deepEqual(deepLink.parseDeepLink('minis://new'),
    { kind: 'new', value: '' });
  assert.deepEqual(deepLink.parseDeepLink('minis://action/new_chat'),
    { kind: 'new', value: '' });
  assert.deepEqual(deepLink.parseDeepLink('minis://action/camera_chat'),
    { kind: 'camera', value: '' });
  assert.equal(deepLink.parseDeepLink('minis://action/voice_chat'), null);
  assert.deepEqual(deepLink.parseDeepLink('minis://settings'),
    { kind: 'settings', value: '' });
  assert.deepEqual(deepLink.parseDeepLink('minis://settings/providers'),
    { kind: 'settings', value: 'providers' });
  assert.deepEqual(deepLink.parseDeepLink('minis://views/alarm'),
    { kind: 'alarm', value: '' });
  assert.equal(deepLink.parseDeepLink('minis://views/other'), null);
  assert.equal(deepLink.parseDeepLink('minis://session/'), null);
  assert.equal(deepLink.parseDeepLink('minis://file/a.txt'), null);
  assert.equal(deepLink.parseDeepLink('https://example.com'), null);
  assert.equal(deepLink.parseDeepLink(''), null);
});

test('minis resource links resolve workspace and attachment files', () => {
  assert.deepEqual(minisResource.parseMinisResource('minis://workspace/notes/a.md'),
    { scope: 'workspace', path: 'notes/a.md' });
  assert.deepEqual(minisResource.parseMinisResource('MINIS://Workspace/%E6%97%A5%E5%BF%97.md'),
    { scope: 'workspace', path: '日志.md' });
  assert.deepEqual(minisResource.parseMinisResource('minis://attachments/pic.png'),
    { scope: 'attachments', path: 'pic.png' });
  assert.deepEqual(minisResource.parseMinisResource('minis://browser/shot-1.png'),
    { scope: 'browser', path: 'shot-1.png' });
  assert.equal(minisResource.resourceUrl('browser', 'shot 1.png'),
    'minis://browser/shot%201.png');
  assert.equal(minisResource.resourceUrl('workspace', 'site/a b.js'),
    'minis://workspace/site/a%20b.js');
  assert.deepEqual(minisResource.parseMinisResource('minis://workspace'),
    { scope: 'workspace', path: '' });
  // Traversal, absolute paths, bad escapes and other hosts are rejected.
  assert.equal(minisResource.parseMinisResource('minis://workspace/../secret'), null);
  assert.equal(minisResource.parseMinisResource('minis://workspace//etc/passwd'), null);
  assert.equal(minisResource.parseMinisResource('minis://workspace/%zz'), null);
  assert.equal(minisResource.parseMinisResource('minis://session/abc'), null);
  assert.equal(minisResource.parseMinisResource('https://example.com/x'), null);
  assert.deepEqual(minisResource.splitResourcePath('notes/a.md'), ['notes', 'a.md']);
  assert.deepEqual(minisResource.splitResourcePath('a.md'), ['', 'a.md']);
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

function anthropicPart(kind, extra = {}) {
  return {
    kind,
    text: '',
    toolCallId: '',
    toolName: '',
    argumentsText: '',
    resultText: '',
    status: 'done',
    isError: false,
    mimeType: '',
    uri: '',
    ...extra
  };
}

function anthropicMessage(role, parts) {
  return {
    id: role + '-' + Math.random().toString(16).slice(2),
    role,
    parts,
    createdAt: 0,
    streaming: false,
    error: false,
    promptTokens: 0,
    completionTokens: 0,
    totalTokens: 0
  };
}

test('Anthropic conversion emits tool_use and matching tool_result blocks', () => {
  const history = [
    anthropicMessage('user', [anthropicPart('text', { text: '看一下这张图' }),
      anthropicPart('image', { uri: 'chat/a.png', mimeType: 'image/png' })]),
    anthropicMessage('assistant', [
      anthropicPart('text', { text: '我来读取。' }),
      anthropicPart('tool_call', {
        toolCallId: 'call_1', toolName: 'read_file',
        argumentsText: '{"path":"a.txt"}', resultText: 'hello', status: 'done'
      }),
      anthropicPart('reasoning', { text: '内部推理应被忽略' })
    ]),
    anthropicMessage('user', [anthropicPart('text', { text: '继续' })])
  ];
  const converted = anthropic.buildAnthropicMessages(history, () =>
    'data:image/png;base64,AAAA');
  assert.equal(converted.messages.length, 3);
  assert.equal(converted.messages[0].role, 'user');
  assert.equal(converted.messages[0].content[0].type, 'text');
  assert.equal(converted.messages[0].content[1].type, 'image');
  assert.equal(converted.messages[0].content[1].source.media_type, 'image/png');
  assert.equal(converted.messages[0].content[1].source.data, 'AAAA');

  const assistant = converted.messages[1];
  assert.equal(assistant.role, 'assistant');
  assert.deepEqual(assistant.content.map((b) => b.type), ['text', 'tool_use']);
  assert.equal(assistant.content[1].id, 'call_1');
  assert.equal(assistant.content[1].name, 'read_file');
  assert.deepEqual(assistant.content[1].input, { path: 'a.txt' });

  const results = converted.messages[2];
  assert.equal(results.role, 'user');
  assert.equal(results.content[0].type, 'tool_result');
  assert.equal(results.content[0].tool_use_id, 'call_1');
  assert.equal(results.content[0].content[0].text, 'hello');
  assert.equal(results.content[0].is_error, false);
  // The following user turn merges into the same user message.
  assert.equal(results.content[1].text, '继续');
});

test('Anthropic conversion dedupes repeated call ids and keeps system text', () => {
  const history = [
    anthropicMessage('system', [anthropicPart('text', { text: '摘要：此前在改设置页' })]),
    anthropicMessage('user', [anthropicPart('text', { text: 'go' })]),
    anthropicMessage('assistant', [
      anthropicPart('tool_call', {
        toolCallId: 'dup', toolName: 'a', argumentsText: '{}', resultText: 'one'
      }),
      anthropicPart('tool_call', {
        toolCallId: 'dup', toolName: 'b', argumentsText: '{}', resultText: 'two'
      })
    ])
  ];
  const converted = anthropic.buildAnthropicMessages(history, null);
  assert.equal(converted.messages.length, 3);
  assert.equal(converted.messages[0].role, 'user');
  assert.equal(converted.messages[0].content[0].text, '摘要：此前在改设置页');
  assert.equal(converted.messages[0].content[1].text, 'go');
  const uses = converted.messages[1].content;
  assert.deepEqual(uses.map((b) => b.id), ['dup', 'dup_2']);
  const results = converted.messages[2].content;
  assert.deepEqual(results.map((b) => b.tool_use_id), ['dup', 'dup_2']);
  assert.deepEqual(results.map((b) => b.content[0].text), ['one', 'two']);
});

test('Anthropic tools and request body follow Messages API shape', () => {
  const defs = anthropic.anthropicTools([
    {
      name: 'read_file',
      description: 'read',
      parameters: { type: 'object', properties: {} },
      schemaJson: '{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}'
    }
  ]);
  assert.equal(defs[0].input_schema.required[0], 'path');

  const body = anthropic.buildAnthropicBody(
    'claude-sonnet-5-5', 4096, 'sys',
    [{ role: 'user', content: [{ type: 'text', text: 'hi' }] }],
    defs, 1.7, 0.3);
  assert.equal(body.temperature, 1);
  assert.equal(body.top_p, 0.3);
  assert.equal(body.max_tokens, 4096);
  assert.equal(body.system, 'sys');
  assert.equal(body.stream, true);
  assert.equal(body.tools.length, 1);

  assert.equal(anthropic.anthropicMessagesUrl('https://api.anthropic.com/v1/'),
    'https://api.anthropic.com/v1/messages');
  assert.equal(anthropic.anthropicMessagesUrl('https://proxy/v1/messages'),
    'https://proxy/v1/messages');
  assert.equal(anthropic.anthropicModelsUrl('https://api.anthropic.com/v1/messages'),
    'https://api.anthropic.com/v1/models');
});

test('Anthropic stream decoder accumulates usage and tool arguments', () => {
  const state = anthropic.newAnthropicStreamState();
  let delta = anthropic.parseAnthropicData(JSON.stringify({
    type: 'message_start',
    message: { usage: { input_tokens: 12 } }
  }), state);
  assert.equal(delta.usage.present, true);
  assert.equal(delta.usage.promptTokens, 12);

  delta = anthropic.parseAnthropicData(JSON.stringify({
    type: 'content_block_start', index: 1,
    content_block: { type: 'tool_use', id: 'toolu_1', name: 'read_file' }
  }), state);
  assert.deepEqual(delta.toolCalls, [
    { index: 1, id: 'toolu_1', name: 'read_file', arguments: '' }
  ]);

  delta = anthropic.parseAnthropicData(JSON.stringify({
    type: 'content_block_delta', index: 1,
    delta: { type: 'input_json_delta', partial_json: '{"path":"a"}' }
  }), state);
  assert.equal(delta.toolCalls[0].arguments, '{"path":"a"}');

  delta = anthropic.parseAnthropicData(JSON.stringify({
    type: 'content_block_delta', index: 0,
    delta: { type: 'text_delta', text: '好的' }
  }), state);
  assert.equal(delta.content, '好的');

  delta = anthropic.parseAnthropicData(JSON.stringify({
    type: 'content_block_delta', index: 0,
    delta: { type: 'thinking_delta', thinking: '嗯' }
  }), state);
  assert.equal(delta.reasoning, '嗯');

  delta = anthropic.parseAnthropicData(JSON.stringify({
    type: 'message_delta',
    delta: { stop_reason: 'tool_use' },
    usage: { output_tokens: 7 }
  }), state);
  assert.equal(delta.finishReason, 'tool_calls');
  assert.equal(delta.usage.completionTokens, 7);
  assert.equal(delta.usage.totalTokens, 19);

  delta = anthropic.parseAnthropicData(JSON.stringify({ type: 'message_stop' }), state);
  assert.equal(delta.done, true);

  delta = anthropic.parseAnthropicData(JSON.stringify({
    type: 'error', error: { type: 'overloaded_error', message: '过载' }
  }), anthropic.newAnthropicStreamState());
  assert.equal(delta.error, '过载');
});

test('Gemini conversion uses model/user roles and functionResponse parts', () => {
  const history = [
    anthropicMessage('user', [anthropicPart('text', { text: '读文件' }),
      anthropicPart('image', { uri: 'chat/a.png', mimeType: 'image/png' })]),
    anthropicMessage('assistant', [
      anthropicPart('text', { text: '好' }),
      anthropicPart('tool_call', {
        toolCallId: 'call_1', toolName: 'read_file',
        argumentsText: '{"path":"a.txt"}', resultText: 'hello'
      })
    ]),
    anthropicMessage('user', [anthropicPart('text', { text: '继续' })])
  ];
  const converted = gemini.buildGeminiContents(history, () =>
    'data:image/jpeg;base64,BBBB');
  assert.equal(converted.contents.length, 3);
  assert.deepEqual(converted.contents.map((c) => c.role), ['user', 'model', 'user']);
  const first = converted.contents[0].parts;
  assert.equal(first[0].text, '读文件');
  assert.equal(first[1].inlineData.mimeType, 'image/jpeg');
  assert.equal(first[1].inlineData.data, 'BBBB');
  const model = converted.contents[1].parts;
  assert.equal(model[0].text, '好');
  assert.equal(model[1].functionCall.name, 'read_file');
  assert.deepEqual(model[1].functionCall.args, { path: 'a.txt' });
  const results = converted.contents[2].parts;
  assert.equal(results[0].functionResponse.name, 'read_file');
  assert.equal(results[0].functionResponse.response.result, 'hello');
  assert.equal(results[1].text, '继续');
});

test('Gemini tools, body and URLs follow generateContent shape', () => {
  const tools = gemini.geminiTools([
    {
      name: 'read_file',
      description: 'read',
      parameters: { type: 'object', properties: {} },
      schemaJson: '{"type":"object","properties":{"path":{"type":"string"}}}'
    }
  ]);
  assert.equal(tools[0].functionDeclarations[0].parameters.properties.path.type, 'string');

  const body = gemini.buildGeminiBody(
    'gemini-2.5-pro', 8192, '系统',
    [{ role: 'user', parts: [{ text: 'hi' }] }],
    tools, 0.7, 0.9);
  assert.equal(body.systemInstruction.parts[0].text, '系统');
  assert.equal(body.generationConfig.maxOutputTokens, 8192);
  assert.equal(body.generationConfig.temperature, 0.7);
  assert.equal(body.generationConfig.topP, 0.9);
  assert.equal(body.tools.length, 1);

  assert.equal(
    gemini.geminiStreamUrl('https://generativelanguage.googleapis.com/v1beta', 'gemini-2.5-pro'),
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:streamGenerateContent?alt=sse');
  assert.equal(
    gemini.geminiStreamUrl('https://proxy/v1beta/models', 'm'),
    'https://proxy/v1beta/models/m:streamGenerateContent?alt=sse');
  assert.equal(
    gemini.geminiGenerateUrl('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent', 'gemini-2.5-pro'),
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent');
  assert.equal(
    gemini.geminiModelsUrl('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent'),
    'https://generativelanguage.googleapis.com/v1beta/models');
});

test('Gemini stream decoder handles text, thought, function calls and usage', () => {
  const state = gemini.newGeminiStreamState();
  let delta = gemini.parseGeminiData(JSON.stringify({
    candidates: [{
      content: {
        role: 'model',
        parts: [
          { text: '先想一下', thought: true },
          { text: '好的' },
          { functionCall: { name: 'read_file', args: { path: 'a.txt' } } }
        ]
      },
      finishReason: 'STOP'
    }],
    usageMetadata: { promptTokenCount: 20, candidatesTokenCount: 8 }
  }), state);
  assert.equal(delta.reasoning, '先想一下');
  assert.equal(delta.content, '好的');
  assert.equal(delta.finishReason, 'stop');
  assert.equal(delta.toolCalls[0].name, 'read_file');
  assert.equal(delta.toolCalls[0].arguments, '{"path":"a.txt"}');
  assert.equal(delta.usage.totalTokens, 28);

  delta = gemini.parseGeminiData(JSON.stringify({
    candidates: [{
      content: { role: 'model', parts: [{ functionCall: { name: 'list_dir' } }] },
      finishReason: 'MAX_TOKENS'
    }]
  }), state);
  assert.equal(delta.finishReason, 'length');
  assert.equal(delta.toolCalls[0].index, 1);

  delta = gemini.parseGeminiData(JSON.stringify({
    promptFeedback: { blockReason: 'SAFETY' }
  }), gemini.newGeminiStreamState());
  assert.equal(delta.error.indexOf('SAFETY') >= 0, true);

  delta = gemini.parseGeminiData(JSON.stringify({
    error: { code: 429, message: '配额不足' }
  }), gemini.newGeminiStreamState());
  assert.equal(delta.error, '配额不足');
});

test('LaTeX converts fractions, roots, scripts and common symbols', () => {
  assert.equal(latex.latexToText('\\frac{a+b}{c}'), '(a+b)/c');
  assert.equal(latex.latexToText('\\sqrt{x^2+y^2}'), '√(x²+y²)');
  assert.equal(latex.latexToText('\\alpha \\le \\beta \\times 2'), 'α ≤ β × 2');
  assert.equal(latex.latexToText('x_i^2'), 'xᵢ²');
  assert.equal(latex.latexToText('\\text{速度} = \\frac{d}{t}'), '速度 = d/t');
  assert.equal(latex.latexToText('\\unknown{x}'), 'x');
  assert.equal(latex.latexToText('\\frac{1}{2}'), '1/2');
});

test('inline math heuristic ignores currency and unclosed dollars', () => {
  const span = latex.inlineMathSpan('质能方程 $E=mc^2$ 成立', 5);
  assert.equal(span.text, 'E=mc^2');
  assert.equal(span.next, 13);
  assert.equal(latex.inlineMathSpan('$5 and $6', 0), null);
  assert.equal(latex.inlineMathSpan('$$x$$', 0), null);
  assert.equal(latex.inlineMathSpan('$x', 0), null);
  assert.equal(latex.inlineMathSpan('$ x $', 0), null);
});

test('Markdown recognizes display and inline math', () => {
  const blocks = md.parseMarkdown('$$\\frac{1}{2}$$');
  assert.equal(blocks[0].kind, 'math');
  assert.equal(blocks[0].text, '1/2');
  assert.equal(blocks[0].raw, '\\frac{1}{2}');

  const inline = md.parseInline('质能方程 $E=mc^2$ 成立');
  assert.equal(inline[0].text, '质能方程 ');
  assert.equal(inline[1].text, 'E=mc²');
  assert.equal(inline[1].math, 'E=mc^2');
  assert.equal(inline[2].text, ' 成立');
  // Non-math spans carry no raw LaTeX marker.
  assert.equal(inline[0].math, undefined);

  const multiline = md.parseMarkdown('$$\na+b\n$$');
  assert.equal(multiline[0].kind, 'math');
  assert.equal(multiline[0].text, 'a+b');
  assert.equal(multiline[0].raw, 'a+b');
});

function sampleJob(id, parent, state) {
  const job = jobs.newJobRecord(id, parent, 'child-' + id, '调研', '看看仓库', 'm', 1000);
  job.state = state;
  return job;
}

test('subagent jobs start queued and label every state', () => {
  const job = jobs.newJobRecord('ab12cd34', 's1', 'c1', '', '任务', 'm1', 5000);
  assert.equal(job.state, 'queued');
  assert.equal(job.steers.length, 0);
  assert.equal(job.finishedAt, 0);
  assert.equal(jobs.isActiveState('queued'), true);
  assert.equal(jobs.isActiveState('running'), true);
  assert.equal(jobs.isActiveState('done'), false);
  assert.equal(jobs.isTerminalState('interrupted'), true);
  assert.equal(jobs.stateLabel('running'), '运行中');
  assert.equal(jobs.stateLabel('timeout'), '超时');
});

test('subagent job ids resolve exactly, by prefix, or report ambiguity', () => {
  const list = [sampleJob('ab12cd34', 's1', 'running'),
    sampleJob('ab34ef56', 's1', 'done'), sampleJob('ff00aa11', 's1', 'done')];
  assert.equal(jobs.matchJobs(list, 'ab12cd34').length, 1);
  assert.equal(jobs.matchJobs(list, 'ff00').length, 1);
  assert.equal(jobs.matchJobs(list, 'ab').length, 2);
  assert.equal(jobs.matchJobs(list, '').length, 3);
  assert.equal(jobs.matchJobs(list, 'zzzz').length, 0);
});

test('subagent status reports state, tool, model and result', () => {
  const list = [sampleJob('ab12cd34', 's1', 'running')];
  list[0].currentTool = 'read_file';
  list[0].modelId = 'gpt-x';
  const report = jobs.statusReport(list, '', 61000);
  assert.match(report, /运行中/);
  assert.match(report, /当前工具：read_file/);
  assert.match(report, /模型：gpt-x/);
  assert.match(report, /已运行 1 分 0 秒/);

  const done = sampleJob('cc00dd11', 's1', 'done');
  jobs.endJob(done, 'done', '结论是 42', 70000);
  const single = jobs.statusReport([done], 'cc00', 80000);
  assert.match(single, /已完成/);
  assert.match(single, /结果：结论是 42/);

  const many = jobs.statusReport([list[0], done], '', 80000);
  assert.match(many, /共 2 个子代理：1 运行中，0 排队中，1 已结束/);
  assert.equal(jobs.statusReport([], '', 0), '这个对话还没有启动过子代理。');
  assert.match(jobs.statusReport([list[0]], 'zzz', 0), /没有匹配/);
  const ambiguous = jobs.statusReport(
    [sampleJob('ab12cd34', 's1', 'running'), sampleJob('ab34ef56', 's1', 'done')],
    'ab', 0);
  assert.match(ambiguous, /匹配了多个/);
});

test('background message carries the prefix, state and result', () => {
  const job = sampleJob('ab12cd34', 's1', 'done');
  jobs.endJob(job, 'done', '完成了调研', 196000);
  const message = jobs.backgroundMessage(job);
  assert.equal(message.startsWith(jobs.BACKGROUND_PREFIX), true);
  assert.match(message, /状态：已完成/);
  assert.match(message, /用时 3 分 15 秒/);
  assert.match(message, /完成了调研/);
  assert.match(message, /job_id=ab12cd34/);

  const empty = sampleJob('ff00aa11', 's1', 'failed');
  jobs.endJob(empty, 'failed', '', 2000);
  assert.match(jobs.backgroundMessage(empty), /（子代理没有返回文本）/);
});

test('elapsed text and pruning stay readable', () => {
  assert.equal(jobs.elapsedText(0), '0 秒');
  assert.equal(jobs.elapsedText(90000), '1 分 30 秒');
  assert.equal(jobs.elapsedText(3 * 3600 * 1000 + 120000), '3 小时 2 分');

  const a = sampleJob('a1', 's1', 'done');
  a.startedAt = 100;
  a.finishedAt = 200;
  const b = sampleJob('b1', 's1', 'done');
  b.startedAt = 200;
  b.finishedAt = 300;
  const c = sampleJob('c1', 's1', 'done');
  c.startedAt = 300;
  c.finishedAt = 400;
  const running = sampleJob('r1', 's1', 'running');
  running.startedAt = 400;
  const kept = jobs.pruneJobs([a, b, c, running], 2);
  assert.deepEqual(kept.map((job) => job.id), ['b1', 'c1', 'r1']);
});

test('web URLs get https and hosts display without noise', () => {
  assert.equal(webUrl.normalizeWebUrl(''), '');
  assert.equal(webUrl.normalizeWebUrl('example.com/a'), 'https://example.com/a');
  assert.equal(webUrl.normalizeWebUrl('HTTP://example.com'), 'HTTP://example.com');
  assert.equal(webUrl.normalizeWebUrl('  https://a.b  '), 'https://a.b');

  assert.equal(webUrl.webHost('https://www.example.com/a?q=1#x'), 'example.com');
  assert.equal(webUrl.webHost('http://user:pass@example.com:8443/path'), 'example.com');
  assert.equal(webUrl.webHost('example.com'), 'example.com');
  assert.equal(webUrl.webHost('https://sub.www.example.com/'), 'sub.www.example.com');
  assert.equal(webUrl.webHost(''), '');
});

test('share card names, truncation and tool summary stay bounded', () => {
  assert.equal(
    shareCard.shareCardFileName('我的/会话', new Date(2026, 10, 8)),
    '我的_会话-2026-11-08-share.png'
  );
  assert.equal(shareCard.shareCardFileName('   ', new Date(2026, 0, 2)),
    '对话-2026-01-02-share.png');

  assert.equal(shareCard.shareCardBody('  你好  '), '你好');
  assert.equal(
    shareCard.shareCardStamp(new Date(2026, 10, 8, 9, 5).getTime()),
    '2026-11-08 09:05'
  );

  const long = 'x'.repeat(shareCard.MAX_SHARE_BODY_CHARS + 50);
  const body = shareCard.shareCardBody(long);
  assert.equal(body.length,
    shareCard.MAX_SHARE_BODY_CHARS + '\n\n…（内容过长，已截断）'.length);
  assert.ok(body.endsWith('…（内容过长，已截断）'));

  const many = [];
  for (let i = 0; i < shareCard.MAX_SHARE_TOOL_LINES + 3; i++) {
    many.push('✓ tool' + i);
  }
  const lines = shareCard.shareCardToolLines(many);
  assert.equal(lines.length, shareCard.MAX_SHARE_TOOL_LINES + 1);
  assert.equal(lines[shareCard.MAX_SHARE_TOOL_LINES], '…还有 3 个工具调用');

  const few = ['✓ a', '✕ b'];
  assert.deepEqual(shareCard.shareCardToolLines(few), ['✓ a', '✕ b']);
  assert.notEqual(shareCard.shareCardToolLines(few), few);
});

test('diagnostics bundle redacts, trims and omits secrets', () => {
  assert.equal(
    diagnostics.diagnosticsFileName(new Date(2026, 10, 8)),
    'minis-diagnostics-2026-11-08.json'
  );

  const crash = JSON.parse(diagnostics.crashLine(
    1700000000000,
    'APP_CRASH',
    '{"reason":"boom sk-abcdef123456 Authorization: Bearer tok_987654"}'
  ));
  assert.equal(crash.ts, 1700000000000);
  assert.equal(crash.event, 'APP_CRASH');
  assert.ok(!crash.params.includes('sk-abcdef123456'));
  assert.ok(!crash.params.includes('tok_987654'));
  assert.match(crash.params, /sk-\*\*\*/);

  const longParams = 'x'.repeat(diagnostics.MAX_CRASH_PARAMS_CHARS + 500);
  const capped = JSON.parse(diagnostics.crashLine(1, 'APP_FREEZE', longParams));
  assert.equal(capped.params.length, diagnostics.MAX_CRASH_PARAMS_CHARS);

  const viewer = diagnostics.formatCrashRecord(
    diagnostics.crashLine(1700000000000, 'APP_CRASH', '{"thread":"main","stack":"at foo"}')
  );
  assert.match(viewer, /APP_CRASH/);
  assert.match(viewer, /"stack": "at foo"/);
  assert.equal(diagnostics.formatCrashRecord('garbage'), 'garbage');

  const crashes = [];
  for (let i = 0; i < diagnostics.MAX_DIAGNOSTIC_CRASH_LINES + 5; i++) {
    crashes.push('{"ts":' + i + '}');
  }
  const events = [];
  for (let i = 0; i < diagnostics.MAX_DIAGNOSTIC_EVENT_LINES + 20; i++) {
    events.push('{"event":"e' + i + '"}');
  }
  const doc = JSON.parse(diagnostics.buildDiagnostics({
    generatedAt: Date.UTC(2026, 10, 8, 0, 0, 0),
    environment: {
      versionName: '1.0.0',
      versionCode: 1000,
      sdkApi: 20,
      deviceModel: 'MatePad Air',
      osVersion: 'HarmonyOS 6.0',
      locale: 'zh'
    },
    counts: { sessions: 3, messages: 42 },
    settings: {
      preset: 'opencode',
      modelId: 'glm-4.6',
      thinkingLevel: 'off',
      temperature: 0.7,
      maxTokens: 4096,
      fallbackModels: 1,
      toolsEnabled: true,
      allowWriteTools: false,
      confirmWriteTools: true,
      imageToolsEnabled: false,
      imageGenEnabled: false,
      clipboardToolsEnabled: false,
      memoryEnabled: true,
      backgroundEnabled: true,
      remoteSandbox: false,
      mcpServers: 0,
      disabledTools: ['shell_execute'],
      appLockEnabled: false,
      loggingEnabled: true
    },
    crashLines: crashes,
    eventLines: events
  }));
  assert.equal(doc.app, 'MinisHarmony');
  assert.equal(doc.kind, 'diagnostics');
  assert.equal(doc.generatedAt, '2026-11-08T00:00:00.000Z');
  assert.equal(doc.counts.messages, 42);
  assert.equal(doc.settings.modelId, 'glm-4.6');
  assert.equal(doc.crashes.length, diagnostics.MAX_DIAGNOSTIC_CRASH_LINES);
  assert.equal(doc.events.length, diagnostics.MAX_DIAGNOSTIC_EVENT_LINES);
  // The settings summary has no field capable of carrying a credential.
  assert.ok(!('apiKey' in doc.settings));
  assert.ok(!('baseUrl' in doc.settings));
  assert.ok(!('sandboxToken' in doc.settings));
});

test('WebDAV URLs and targets are normalized and bounded', () => {
  assert.equal(webDav.normalizeWebDavUrl(' https://dav.example.com/minis/// '),
    'https://dav.example.com/minis');
  assert.equal(webDav.normalizeWebDavUrl('HTTP://x/y/'), 'HTTP://x/y');
  assert.equal(webDav.normalizeWebDavUrl('ftp://dav.example.com'), '');
  assert.equal(webDav.normalizeWebDavUrl('dav.example.com/minis'), '');
  assert.equal(webDav.normalizeWebDavUrl('https://'), '');
  assert.equal(webDav.normalizeWebDavUrl('   '), '');

  assert.equal(
    webDav.webDavFileUrl('https://dav.example.com/minis/', 'a.json'),
    'https://dav.example.com/minis/a.json'
  );
  assert.equal(webDav.webDavFileUrl('', 'a.json'), '');

  const targets = webDav.webDavUploadTargets(
    'https://dav.example.com/minis', new Date(2026, 10, 8));
  assert.deepEqual(targets, [
    'https://dav.example.com/minis/minis-backup-2026-11-08-enc.json',
    'https://dav.example.com/minis/' + webDav.WEBDAV_LATEST_NAME
  ]);
  assert.equal(webDav.webDavUploadTargets('bad', new Date()).length, 0);
});

test('backup redaction clears every credential including WebDAV', () => {
  const settings = types.defaultSettings();
  settings.apiKey = 'sk-secret-value';
  settings.sandboxToken = 'sandbox-token';
  settings.webDavUrl = 'https://dav.example.com/minis';
  settings.webDavUser = 'me';
  settings.webDavPassword = 'dav-password';
  const redacted = backup.redactedSettings(settings);
  assert.equal(redacted.apiKey, '');
  assert.equal(redacted.sandboxToken, '');
  assert.equal(redacted.webDavPassword, '');
  // Non-secret remote configuration survives so restore points at the folder.
  assert.equal(redacted.webDavUrl, 'https://dav.example.com/minis');
  assert.equal(redacted.webDavUser, 'me');

  const text = backup.backupJson(settings, [], new Date(2026, 10, 8));
  assert.ok(!text.includes('dav-password'));
  assert.ok(!text.includes('sk-secret-value'));
  assert.ok(!text.includes('sandbox-token'));

  const restored = backup.parseBackupSettings(text);
  assert.equal(restored.webDavUrl, 'https://dav.example.com/minis');
  assert.equal(restored.webDavUser, 'me');
  assert.equal(restored.webDavPassword, '');

  const merged = backup.mergeBackupSettings(settings, restored);
  assert.equal(merged.webDavPassword, 'dav-password');
  assert.equal(merged.apiKey, 'sk-secret-value');
});

test('scheduled task titles and notification text are single-line and capped', () => {
  assert.equal(scheduled.taskTitle('  # 总结今天的邮件  '), '总结今天的邮件');
  assert.equal(scheduled.taskTitle(''), '定时任务');
  assert.equal(scheduled.taskTitle('   \n\t '), '定时任务');
  const longLine = '一'.repeat(40);
  assert.equal(scheduled.taskTitle(longLine), '一'.repeat(20) + '…');
  assert.equal(scheduled.taskNotificationContent('第一行\n第二行'), '第一行 第二行');
  assert.equal(scheduled.taskNotificationContent('  '), '点击填入提示词');
  assert.equal(scheduled.taskNotificationContent('y'.repeat(100)).length, 81);
});

test('scheduled task prompt is trimmed and capped', () => {
  assert.equal(scheduled.normalizeTaskPrompt('  hello  '), 'hello');
  const over = 'x'.repeat(scheduled.MAX_TASK_PROMPT + 50);
  assert.equal(scheduled.normalizeTaskPrompt(over).length, scheduled.MAX_TASK_PROMPT);
});

test('validateTaskAt enforces a one-minute lead and one-year horizon', () => {
  const now = new Date(2026, 10, 8, 9, 0, 0).getTime();
  assert.equal(scheduled.validateTaskAt(now + 2 * 60 * 1000, now), '');
  assert.match(scheduled.validateTaskAt(now + 30 * 1000, now), /1 分钟/);
  assert.match(scheduled.validateTaskAt(now - 1000, now), /1 分钟/);
  assert.match(scheduled.validateTaskAt(now + 400 * 24 * 60 * 60 * 1000, now), /一年/);
  assert.equal(scheduled.validateTaskAt(0, now), '请选择提醒时间');
});

test('formatTaskTime distinguishes today, tomorrow and other dates', () => {
  const now = new Date(2026, 10, 8, 9, 0, 0).getTime();
  const today = new Date(2026, 10, 8, 18, 5, 0).getTime();
  const tomorrow = new Date(2026, 10, 9, 8, 0, 0).getTime();
  const later = new Date(2026, 11, 24, 7, 30, 0).getTime();
  const nextYear = new Date(2027, 0, 2, 7, 30, 0).getTime();
  assert.equal(scheduled.formatTaskTime(today, now), '今天 18:05');
  assert.equal(scheduled.formatTaskTime(tomorrow, now), '明天 08:00');
  assert.equal(scheduled.formatTaskTime(later, now), '12-24 07:30');
  assert.equal(scheduled.formatTaskTime(nextYear, now), '2027-01-02 07:30');
});

test('tasks sort by time and parse defensively', () => {
  const now = Date.now();
  const late = scheduled.makeTask('b', 'later', now + 7200 * 1000, now);
  const early = scheduled.makeTask('a', 'sooner', now + 3600 * 1000, now);
  const sorted = scheduled.sortTasks([late, early]);
  assert.deepEqual(sorted.map((t) => t.id), ['a', 'b']);

  const text = scheduled.tasksJson([late, early]);
  const parsed = scheduled.parseTasks(text);
  assert.deepEqual(parsed.map((t) => t.id), ['a', 'b']);
  assert.equal(parsed[0].reminderId, 0);

  assert.deepEqual(scheduled.parseTasks('not json'), []);
  assert.deepEqual(scheduled.parseTasks('{"id":"x"}'), []);
  const filtered = scheduled.parseTasks(JSON.stringify([
    { id: 'ok', prompt: ' 真实任务 ', at: now + 60000 },
    { id: '', prompt: 'no id', at: now + 60000 },
    { id: 'empty', prompt: '   ', at: now + 60000 }
  ]));
  assert.equal(filtered.length, 1);
  assert.equal(filtered[0].prompt, '真实任务');
});

test('task runs record outcome and keep only the newest 50', () => {
  const task = scheduled.makeTask('t1', '晨间简报', 0, 0);
  const okRun = scheduled.makeRun('r1', task, 1000, '  今天的天气晴朗。 ', '', 2000);
  assert.equal(okRun.ok, true);
  assert.equal(okRun.title, '晨间简报');
  assert.equal(okRun.summary, '今天的天气晴朗。');
  const failed = scheduled.makeRun('r2', task, 1000, '', '网络不可用', 2000);
  assert.equal(failed.ok, false);
  assert.equal(failed.summary, '网络不可用');
  const empty = scheduled.makeRun('r3', task, 1000, '', '', 2000);
  assert.equal(empty.ok, false);
  assert.equal(empty.summary, '没有返回内容');

  const runs = [];
  for (let i = 0; i < scheduled.MAX_TASK_RUNS + 8; i++) {
    runs.push({
      id: 'run-' + i,
      taskId: 't1',
      title: '任务',
      startedAt: i,
      finishedAt: i,
      ok: true,
      summary: ''
    });
  }
  const trimmed = scheduled.trimRuns(runs);
  assert.equal(trimmed.length, scheduled.MAX_TASK_RUNS);
  assert.equal(trimmed[0].id, 'run-' + (scheduled.MAX_TASK_RUNS + 7));
  assert.equal(trimmed[trimmed.length - 1].id, 'run-8');

  const parsed = scheduled.parseRuns(scheduled.runsJson(runs));
  assert.equal(parsed.length, scheduled.MAX_TASK_RUNS);
  assert.deepEqual(scheduled.parseRuns(''), []);
  assert.deepEqual(scheduled.parseRuns('{}'), []);
});

test('parseTimeArg accepts common shapes and rejects nonsense', () => {
  const now = new Date(2026, 10, 8, 12, 0, 0).getTime();
  assert.equal(device.parseTimeArg('2026-11-08 09:30', now),
    new Date(2026, 10, 8, 9, 30, 0).getTime());
  assert.equal(device.parseTimeArg('2026-11-08T09:30:15', now),
    new Date(2026, 10, 8, 9, 30, 15).getTime());
  assert.equal(device.parseTimeArg('2026-11-08', now),
    new Date(2026, 10, 8, 0, 0, 0).getTime());
  assert.equal(device.parseTimeArg('08:05', now),
    new Date(2026, 10, 8, 8, 5, 0).getTime());
  assert.equal(device.parseTimeArg('1700000000000', now), 1700000000000);
  assert.equal(device.parseTimeArg('1700000000', now), 1700000000 * 1000);
  assert.equal(device.parseTimeArg('2026-13-08', now), -1);
  assert.equal(device.parseTimeArg('tomorrow-ish', now), -1);
  assert.equal(device.parseTimeArg('', now), -1);
  assert.equal(device.formatDateTime(new Date(2026, 10, 8, 9, 5).getTime()),
    '2026-11-08 09:05');
});

test('weather helpers map WMO codes and clamp days', () => {
  assert.equal(device.weatherCodeText(0), '晴');
  assert.equal(device.weatherCodeText(3), '阴');
  assert.equal(device.weatherCodeText(63), '中雨');
  assert.equal(device.weatherCodeText(95), '雷暴');
  assert.equal(device.weatherCodeText(999), '未知天气');
  assert.equal(device.clampWeatherDays(0), 1);
  assert.equal(device.clampWeatherDays(99), device.MAX_WEATHER_DAYS);
  assert.equal(device.clampWeatherDays(3.7), 3);
  const url = device.weatherUrl(39.9, 116.4, 20);
  assert.ok(url.includes('latitude=39.9'));
  assert.ok(url.includes('longitude=116.4'));
  assert.ok(url.includes('forecast_days=7'));
  assert.ok(device.geocodeUrl('北京 朝阳').includes(encodeURIComponent('北京 朝阳')));
});

test('weather and geocode JSON parse defensively', () => {
  const geo = device.parseGeoJson(JSON.stringify({
    results: [{ name: '北京', country: '中国', admin1: '北京市', latitude: 39.9, longitude: 116.4 }]
  }));
  assert.equal(geo.name, '北京');
  assert.equal(geo.latitude, 39.9);
  assert.equal(device.parseGeoJson('{"results":[]}'), null);
  assert.equal(device.parseGeoJson('not json'), null);
  assert.equal(device.parseGeoJson('{"results":[{"name":"x"}]}'), null);

  const report = device.parseWeatherJson(JSON.stringify({
    current: {
      time: '2026-11-08T09:00',
      temperature_2m: 12.3,
      apparent_temperature: 10.1,
      relative_humidity_2m: 55,
      wind_speed_10m: 8.2,
      precipitation: 0,
      weather_code: 2
    },
    daily: {
      time: ['2026-11-08', '2026-11-09'],
      weather_code: [2, 61],
      temperature_2m_max: [15, 13],
      temperature_2m_min: [6, 5],
      precipitation_probability_max: [10, 70]
    }
  }));
  assert.equal(report.current.temperature, 12.3);
  assert.equal(report.current.code, 2);
  assert.equal(report.days.length, 2);
  assert.equal(report.days[1].code, 61);
  assert.equal(report.days[1].precipitationProbability, 70);
  const text = device.formatWeatherText('北京 · 中国', report);
  assert.ok(text.includes('多云'));
  assert.ok(text.includes('12.3°C'));
  assert.ok(text.includes('2026-11-09'));

  const empty = device.parseWeatherJson('{}');
  assert.equal(empty.current, null);
  assert.deepEqual(empty.days, []);
  assert.equal(device.parseWeatherJson('garbage').days.length, 0);
});

test('event and contact formatting stays compact', () => {
  const start = new Date(2026, 10, 8, 9, 0).getTime();
  const end = new Date(2026, 10, 8, 10, 30).getTime();
  assert.equal(device.formatEventLine(7, '周会', start, end, '会议室'),
    '7 | 2026-11-08 09:00–10:30 | 周会 | 会议室');
  assert.equal(device.formatEventLine(7, '周会', start, start, ''),
    '7 | 2026-11-08 09:00– | 周会');
  assert.equal(device.formatContactBlock('张三', ['13800000000'], ['a@b.c']),
    '张三 · 13800000000 · a@b.c');
  assert.equal(device.formatContactBlock('', [], []), '（未命名）');
  assert.equal(device.formatContactBlock('李四',
    ['1', '2', '3', '4'], ['x', 'y', 'z']), '李四 · 1 / 2 / 3 · x / y');
});

test('python_execute schema advertises code and a bounded timeout', () => {
  const tools = catalog.builtinToolDefinitions();
  const tool = tools.find((item) => item.name === 'python_execute');
  assert.notEqual(tool, undefined);
  assert.deepEqual(tool.parameters.required, ['code']);
  assert.equal(tool.parameters.properties.code.type, 'string');
  assert.equal(tool.parameters.properties.timeout.type, 'number');
  // The description must tell the model that state survives between calls;
  // otherwise it will re-import modules on every request.
  assert.match(tool.description, /常驻/);
  assert.match(tool.parameters.properties.timeout.description, /120/);
});

test('browser_use schema covers interactive, cookie and screenshot actions', () => {
  const tools = catalog.builtinToolDefinitions();
  const tool = tools.find((item) => item.name === 'browser_use');
  assert.notEqual(tool, undefined);
  assert.deepEqual(tool.parameters.required, ['action']);
  for (const name of ['direction', 'amount', 'item_selector', 'scroll_count',
    'cookies', 'user_agent', 'max_depth', 'timeout',
    'viewport_width', 'viewport_height', 'reset', 'keyword', 'fuzzy', 'tab_id']) {
    assert.notEqual(tool.parameters.properties[name], undefined, name);
  }
  assert.equal(tool.parameters.properties.amount.type, 'number');
  assert.match(tool.parameters.properties.action.description, /screenshot/);
  assert.match(tool.parameters.properties.action.description, /get_readable/);
  assert.match(tool.description, /minis:\/\/workspace/);
});

test('device tool schema advertises the four capabilities', () => {
  const tools = catalog.builtinToolDefinitions();
  for (const name of ['calendar', 'contacts', 'location', 'weather']) {
    const tool = tools.find((item) => item.name === name);
    assert.notEqual(tool, undefined, name);
    assert.equal(tool.parameters.type, 'object');
  }
});

function syncSession(id, updatedAt, text) {
  return {
    meta: {
      id: id,
      title: 'T-' + id,
      updatedAt: updatedAt,
      modelId: 'm',
      messageCount: text.length > 0 ? 1 : 0,
      pinned: false,
      archived: false,
      modelOverride: '',
      thinkingOverride: '',
      promptOverride: ''
    },
    messages: text.length > 0
      ? [{ id: 'msg-' + id, role: 'user', parts: [{ kind: 'text', text: text }], createdAt: updatedAt }]
      : []
  };
}

test('sync merge keeps the newest copy and never drops local sessions', () => {
  const local = [
    syncSession('a', 100, 'local-a'),
    syncSession('b', 300, 'local-b'),
    syncSession('c', 500, 'local-c')
  ];
  const remote = [
    syncSession('a', 200, 'remote-a'),
    syncSession('b', 100, 'remote-b'),
    syncSession('d', 400, 'remote-d')
  ];
  const out = syncMerge.mergeSessionSets(local, remote);
  assert.equal(out.addedFromRemote, 1);
  assert.equal(out.updatedFromRemote, 1);
  assert.equal(out.keptLocal, 1);
  assert.equal(out.sessions.length, 4);
  const byId = new Map(out.sessions.map((s) => [s.meta.id, s]));
  assert.equal(byId.get('a').messages[0].parts[0].text, 'remote-a');
  assert.equal(byId.get('b').messages[0].parts[0].text, 'local-b');
  assert.equal(byId.get('c').messages[0].parts[0].text, 'local-c');
  assert.equal(byId.get('d').messages[0].parts[0].text, 'remote-d');
  // Newest first, matching the session list order.
  assert.deepEqual(out.sessions.map((s) => s.meta.id), ['c', 'd', 'b', 'a']);
  assert.equal(syncMerge.remoteChangeCount(local, remote), 2);
});

test('sync merge breaks timestamp ties toward the side with messages', () => {
  const local = [syncSession('x', 42, '')];
  const remote = [syncSession('x', 42, 'remote')];
  const out = syncMerge.mergeSessionSets(local, remote);
  assert.equal(out.updatedFromRemote, 1);
  assert.equal(out.sessions[0].messages.length, 1);

  const reverse = syncMerge.mergeSessionSets(remote, local);
  assert.equal(reverse.updatedFromRemote, 0);
  assert.equal(reverse.keptLocal, 1);
  assert.equal(reverse.sessions[0].messages.length, 1);
});

test('backup parse preserves ids and timestamps for merging', () => {
  const now = new Date('2026-11-08T10:00:00Z');
  const sessions = [syncSession('keep-1', 123456, 'hello')];
  const text = backup.backupJson(types.defaultSettings(), sessions, now);
  const parsed = sessionExport.parseBackupSessions(text, now);
  assert.equal(parsed.ok, true);
  assert.equal(parsed.sessions.length, 1);
  assert.equal(parsed.sessions[0].meta.id, 'keep-1');
  assert.equal(parsed.sessions[0].meta.updatedAt, 123456);
  assert.ok(!parsed.sessions[0].meta.title.endsWith('（导入）'));

  // A remote copy identical to the local one changes nothing.
  const merged = syncMerge.mergeSessionSets(parsed.sessions, parsed.sessions);
  assert.equal(merged.addedFromRemote, 0);
  assert.equal(merged.updatedFromRemote, 0);
  assert.equal(merged.sessions.length, 1);
  assert.equal(sessionExport.parseBackupSessions('{"app":"other"}', now).ok, false);
});

test('PKCE base64url keeps the RFC alphabet without padding', () => {
  assert.equal(oauth.base64UrlEncode(new Uint8Array([])), '');
  assert.equal(oauth.base64UrlEncode(new Uint8Array([0])), 'AA');
  assert.equal(oauth.base64UrlEncode(new Uint8Array([97, 98, 99])), 'YWJj');
  assert.equal(oauth.base64UrlEncode(new Uint8Array([255, 254])), '__4');
  assert.equal(oauth.base64UrlEncode(new Uint8Array([251, 255])), '-_8');
  const verifier = oauth.pkceVerifierFromBytes(new Uint8Array(64).fill(7));
  assert.equal(verifier.length, 86);
  assert.ok(!verifier.includes('='));
  assert.ok(!verifier.includes('+'));
  assert.ok(!verifier.includes('/'));
});

test('authorization URL carries PKCE and provider extras', () => {
  const claude = oauth.authorizeUrl('claude', 'CHALLENGE', 'STATE');
  assert.ok(claude.startsWith('https://claude.ai/oauth/authorize?response_type=code'));
  assert.ok(claude.includes('client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e'));
  assert.ok(claude.includes('redirect_uri=http%3A%2F%2Flocalhost%3A54545%2Fcallback'));
  assert.ok(claude.includes('code_challenge=CHALLENGE'));
  assert.ok(claude.includes('code_challenge_method=S256'));
  assert.ok(claude.includes('state=STATE'));
  assert.ok(claude.includes('user%3Ainference'));

  const codex = oauth.authorizeUrl('codex', 'C', 'S');
  assert.ok(codex.includes('originator=codex_cli_rs'));
  assert.ok(codex.includes('id_token_add_organizations=true'));

  assert.equal(oauth.authorizeUrl('copilot', 'C', 'S'), '');
});

test('pasted callback accepts URL, code#state or bare code', () => {
  const full = oauth.extractRedirectCode(
    'http://localhost:54545/callback?code=abc%2F123&state=xyz');
  assert.deepEqual(full, { code: 'abc/123', state: 'xyz' });

  const hash = oauth.extractRedirectCode('abc123#state456');
  assert.deepEqual(hash, { code: 'abc123', state: 'state456' });

  assert.deepEqual(oauth.extractRedirectCode('  rawcode  '),
    { code: 'rawcode', state: '' });
  assert.equal(oauth.extractRedirectCode('http://localhost:54545/callback?error=access_denied'),
    null);
  assert.equal(oauth.extractRedirectCode('   '), null);
  assert.equal(oauth.extractRedirectCode('http://localhost:54545/callback?state=x'), null);
});

test('token parsing records expiry and tolerates missing fields', () => {
  const now = 1000000;
  const token = oauth.tokenFromJson(JSON.stringify({
    access_token: 'at-1',
    refresh_token: 'rt-1',
    expires_in: 3600
  }), now);
  assert.equal(token.accessToken, 'at-1');
  assert.equal(token.refreshToken, 'rt-1');
  assert.equal(token.expiresAt, now + 3600000);
  assert.equal(oauth.tokenNeedsRefresh(token, now), false);
  assert.equal(oauth.tokenNeedsRefresh(token, now + 3600000 - 60000), true);

  const noExpiry = oauth.tokenFromJson('{"access_token":"at-2"}', now);
  assert.equal(noExpiry.expiresAt, 0);
  assert.equal(oauth.tokenNeedsRefresh(noExpiry, now + 999999999), false);
  assert.equal(oauth.tokenFromJson('{"nope":1}', now), null);
  assert.equal(oauth.tokenFromJson('garbage', now), null);

  const roundtrip = oauth.parseTokenJson(oauth.tokenJson(token));
  assert.equal(roundtrip.accessToken, 'at-1');
  assert.equal(roundtrip.expiresAt, token.expiresAt);
  assert.equal(oauth.parseTokenJson(''), null);
});

test('token masking keeps a recognisable prefix and suffix', () => {
  assert.equal(oauth.maskToken(''), '');
  assert.equal(oauth.maskToken('abc'), '***');
  const masked = oauth.maskToken('sk-ant-oat01-abcdefghijklmnop');
  assert.ok(masked.startsWith('sk-ant-oa'));
  assert.ok(masked.endsWith('hijklmnop'));
  assert.ok(masked.includes('**********'));
  assert.ok(!masked.includes('abcdefghij'));
});

test('device flow and Copilot session parsing', () => {
  const auth = oauth.parseDeviceAuthorization(JSON.stringify({
    device_code: 'dc',
    user_code: 'ABCD-1234',
    verification_uri: 'https://github.com/login/device',
    expires_in: 900,
    interval: 5
  }));
  assert.equal(auth.deviceCode, 'dc');
  assert.equal(auth.userCode, 'ABCD-1234');
  assert.equal(auth.interval, 5);
  assert.equal(oauth.parseDeviceAuthorization('{}'), null);

  assert.equal(oauth.classifyDevicePoll('{"access_token":"gho_x"}', true).kind, 'success');
  assert.equal(oauth.classifyDevicePoll(
    '{"error":"authorization_pending"}', true).kind, 'pending');
  assert.equal(oauth.classifyDevicePoll('{"error":"slow_down"}', true).kind, 'slow_down');
  assert.equal(oauth.classifyDevicePoll('{"error":"access_denied"}', true).kind, 'denied');
  assert.equal(oauth.classifyDevicePoll('{"error":"expired_token"}', true).kind, 'expired');
  assert.equal(oauth.classifyDevicePoll('{"error":"unauthorized_client"}', true).kind,
    'fatal');
  assert.equal(oauth.classifyDevicePoll('not json', false).kind, 'fatal');
  assert.equal(oauth.bumpedDeviceInterval(5), 10);

  const session = oauth.parseCopilotSession(
    '{"token":"copilot-session","expires_at":1700000000}', 1);
  assert.equal(session.token, 'copilot-session');
  assert.equal(session.expiresAt, 1700000000000);
  const fallback = oauth.parseCopilotSession('{"token":"t"}', 1000);
  assert.equal(fallback.expiresAt, 1000 + 25 * 60 * 1000);
  assert.equal(oauth.parseCopilotSession('{}', 0), null);

  const storage = {
    githubToken: 'gho_test',
    sessionToken: 'copilot-session',
    sessionExpiresAt: 1700000000000
  };
  const roundtrip = oauth.parseCopilotStorage(oauth.copilotStorageJson(storage));
  assert.deepEqual(roundtrip, storage);
  assert.equal(oauth.parseCopilotStorage(''), null);
  assert.equal(oauth.parseCopilotStorage('{"sessionToken":"x"}'), null);
  const sparse = oauth.parseCopilotStorage('{"githubToken":"gho_min"}');
  assert.equal(sparse.sessionToken, '');
  assert.equal(sparse.sessionExpiresAt, 0);
  assert.equal(oauth.parseCopilotStorage('not json'), null);
});

test('JWT claims and payload segment extraction', () => {
  const claims = oauth.jwtClaimsFromPayloadJson(JSON.stringify({
    chatgpt_account_id: 'acc-1',
    chatgpt_plan_type: 'plus',
    email: 'a@b.c'
  }));
  assert.equal(claims.chatgptAccountId, 'acc-1');
  assert.equal(claims.chatgptPlanType, 'plus');
  assert.equal(claims.email, 'a@b.c');
  assert.equal(oauth.jwtPayloadSegment('a.b.c'), 'b');
  assert.equal(oauth.jwtPayloadSegment('nodots'), '');
  assert.equal(oauth.jwtClaimsFromPayloadJson('bad').chatgptAccountId, '');
});

test('truncateMiddle keeps both ends and counts the omission', () => {
  assert.equal(terminal.truncateMiddle('abc', 10), 'abc');
  const text = 'HEAD' + 'x'.repeat(100) + 'TAIL';
  const cut = terminal.truncateMiddle(text, 20);
  assert.ok(cut.startsWith('HEAD'));
  assert.ok(cut.endsWith('TAIL'));
  assert.ok(cut.includes('88 characters omitted'));
  assert.equal(terminal.truncateMiddle('abc', 0), 'abc');
});

test('sanitizeTerminal strips ANSI colours and OSC sequences', () => {
  assert.equal(
    terminal.sanitizeTerminal('\x1B[31merror\x1B[0m: bad'),
    'error: bad');
  assert.equal(
    terminal.sanitizeTerminal('\x1B]0;title\x07visible'),
    'visible');
  assert.equal(
    terminal.sanitizeTerminal('a\x1B[Kb'),
    'ab');
});

test('sanitizeTerminal folds carriage-return overwrites like a terminal', () => {
  // Each \r moves to column 0; a shorter write leaves the old tail visible.
  assert.equal(terminal.sanitizeTerminal('AAAA\rBB'), 'BBAA');
  assert.equal(terminal.sanitizeTerminal('progress 50%\rdone'), 'doneress 50%');
  // ESC[K erases to the end of the line before the next write.
  assert.equal(
    terminal.sanitizeTerminal('Downloading 50%\r\x1B[KDone'),
    'Done');
  // Escapes take no columns when the cursor is simulated.
  assert.equal(
    terminal.sanitizeTerminal('\x1B[32mOK\x1B[0m\rfine'),
    'fine');
});

test('sanitizeTerminal drops control bytes and blank-line runs', () => {
  assert.equal(
    terminal.sanitizeTerminal('a\x00b\x07c'),
    'abc');
  assert.equal(
    terminal.sanitizeTerminal('one\n\n\n\ntwo\n'),
    'one\n\ntwo');
  assert.equal(terminal.sanitizeTerminal(''), '');
});

test('sanitizeTerminal bounds huge input before rewriting', () => {
  const huge = 'a'.repeat(500000);
  const cleaned = terminal.sanitizeTerminal(huge);
  assert.ok(cleaned.length < 401000, 'output stays near the pre-trim cap');
  assert.ok(cleaned.includes('characters omitted'));
});

test('sandbox marker parsing matches the command id only', () => {
  const text = 'hello\n[sandbox exit=0 id=7]\n';
  const marker = sandboxProtocol.findSandboxMarker(text, 0, 7);
  assert.equal(marker.code, 0);
  assert.equal(marker.index, 6);
  assert.equal(text.substring(marker.index, marker.end), '[sandbox exit=0 id=7]');

  // A late marker from a command whose caller gave up must not match.
  assert.equal(sandboxProtocol.findSandboxMarker(text, 0, 8), null);
  // Negative and multi-digit codes survive the parse.
  assert.equal(
    sandboxProtocol.findSandboxMarker('[sandbox exit=-1 id=2]', 0, 2).code, -1);
  assert.equal(
    sandboxProtocol.findSandboxMarker('[sandbox exit=128 id=2]', 0, 2).code, 128);
  // An unterminated marker means the line is still arriving.
  assert.equal(sandboxProtocol.findSandboxMarker('[sandbox exit=0 id=7', 0, 7), null);
  // Scanning starts at `from`, and skips markers for other ids.
  const two = '[sandbox exit=1 id=3]\n[sandbox exit=0 id=4]';
  assert.equal(sandboxProtocol.findSandboxMarker(two, 0, 4).code, 0);
  assert.equal(sandboxProtocol.findSandboxMarker(two, 25, 3), null);
});

test('sandbox command payload matches the harness framing', () => {
  assert.equal(sandboxProtocol.commandPayload(12, 'ls -la'), 'id=12\nls -la');
  assert.equal(sandboxProtocol.utf8ByteLength('abc'), 3);
  assert.equal(sandboxProtocol.utf8ByteLength('中文'), 6);
  assert.equal(sandboxProtocol.utf8ByteLength('😀'), 4);
  assert.equal(sandboxProtocol.utf8ByteLength('a中😀'), 8);
  // id=1\n is five bytes; fill exactly to the 16000-byte limit.
  assert.equal(sandboxProtocol.commandTooLong('id=1\n' + 'a'.repeat(15995)), false);
  assert.equal(sandboxProtocol.commandTooLong('id=1\n' + 'a'.repeat(15996)), true);
  // Bytes, not UTF-16 units: 5400 Chinese chars are 16200 bytes.
  assert.equal(sandboxProtocol.commandTooLong('id=1\n' + '中'.repeat(5400)), true);
});

test('sandbox request payload is one key per line', () => {
  const payload = sandboxProtocol.sandboxRequestPayload(
    '/r', '/o', '/c', '/w', '/m', '/a', '/s');
  assert.equal(payload,
    'rootfs=/r\noutput=/o\ncommands=/c\nworkspace=/w\nmemory=/m\nattachments=/a\n' +
    'skills=/s\n');
});

test('responses url derivation', () => {
  assert.equal(responses.responsesUrl('https://chatgpt.com/backend-api/codex'),
    'https://chatgpt.com/backend-api/codex/responses');
  // Trailing slashes and an already-complete route are left alone.
  assert.equal(responses.responsesUrl('https://proxy.example/v1/responses/'),
    'https://proxy.example/v1/responses');
  assert.equal(responses.responsesUrl('  https://proxy.example/v1///  '),
    'https://proxy.example/v1/responses');
  assert.equal(responses.codexModelsUrl('https://chatgpt.com/backend-api/codex'),
    'https://chatgpt.com/backend-api/codex/models');
  // Discovery hangs off the base, not the inference route.
  assert.equal(responses.codexModelsUrl('https://chatgpt.com/backend-api/codex/responses'),
    'https://chatgpt.com/backend-api/codex/models');
  assert.equal(responses.codexModelsUrl('https://proxy.example/models'),
    'https://proxy.example/models');
});

test('responses tool ids carry call_id and item_id', () => {
  assert.equal(responses.combineResponsesIds('call_1', 'fc_1'), 'call_1|fc_1');
  assert.equal(responses.combineResponsesIds('call_1', ''), 'call_1');
  assert.equal(responses.callIdPart('call_1|fc_1'), 'call_1');
  assert.equal(responses.callIdPart('call_1'), 'call_1');
  // An id that already contains a bar keeps only the prefix.
  assert.equal(responses.callIdPart('a|b|c'), 'a');
});

test('responses input conversion', () => {
  const messages = [
    { role: 'system', content: 'You are Minis.' },
    { role: 'system', content: 'Be terse.' },
    { role: 'user', content: 'hello' },
    {
      role: 'user',
      content: [
        { type: 'text', text: 'look' },
        { type: 'image_url', image_url: { url: 'data:image/png;base64,AAA' } },
        { type: 'text', text: '' }
      ]
    },
    {
      role: 'assistant',
      content: 'running',
      tool_calls: [{
        id: 'call_9|fc_9',
        function: { name: 'shell', arguments: '{"command":"ls"}' }
      }]
    },
    { role: 'tool', tool_call_id: 'call_9|fc_9', content: 'a.txt' }
  ];
  assert.equal(responses.responsesInstructions(messages), 'You are Minis.\n\nBe terse.');
  const input = responses.buildResponsesInput(messages);
  // System turns are hoisted into `instructions`, not repeated as items.
  assert.deepEqual(input[0], { role: 'user', content: 'hello' });
  assert.deepEqual(input[1], {
    role: 'user',
    content: [
      { type: 'input_text', text: 'look' },
      { type: 'input_image', image_url: 'data:image/png;base64,AAA' }
    ]
  });
  assert.deepEqual(input[2], { role: 'assistant', content: 'running' });
  assert.deepEqual(input[3], {
    type: 'function_call',
    id: 'fc_9',
    call_id: 'call_9',
    name: 'shell',
    arguments: '{"command":"ls"}'
  });
  // Tool output echoes the bare call id, not the combined form.
  assert.deepEqual(input[4], {
    type: 'function_call_output',
    call_id: 'call_9',
    output: 'a.txt'
  });
});

test('responses synthesises item ids for imported tool calls', () => {
  const input = responses.buildResponsesInput([{
    role: 'assistant',
    content: '',
    tool_calls: [{ id: 'call_x', function: { name: 'read', arguments: '' } }]
  }]);
  // Empty arguments still need valid JSON for replays.
  assert.deepEqual(input[0], {
    type: 'function_call',
    id: 'fc_syn_call_x',
    call_id: 'call_x',
    name: 'read',
    arguments: '{}'
  });
});

test('responses tools are flat objects', () => {
  const tools = responses.buildResponsesTools([{
    name: 'shell',
    description: 'Run a command',
    parameters: { type: 'object', properties: { command: { type: 'string' } } },
    schemaJson: '{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}'
  }]);
  assert.equal(tools[0].type, 'function');
  assert.equal(tools[0].name, 'shell');
  assert.equal(tools[0].strict, false);
  // `schemaJson` wins over the pre-parsed object, keeping `required`.
  assert.deepEqual(tools[0].parameters.required, ['command']);
  const broken = responses.buildResponsesTools([{
    name: 't', description: 'd', parameters: { type: 'object' }, schemaJson: '{oops'
  }]);
  assert.deepEqual(broken[0].parameters, { type: 'object' });
});

test('responses prompt cache key follows the first user turn', () => {
  const a = responses.promptCacheKey([
    { role: 'system', content: 'sys' },
    { role: 'user', content: 'first question' },
    { role: 'user', content: 'second' }
  ]);
  const b = responses.promptCacheKey([
    { role: 'system', content: 'different' },
    { role: 'user', content: 'first question' }
  ]);
  const c = responses.promptCacheKey([{ role: 'user', content: 'another chat' }]);
  assert.match(a, /^minis-[0-9a-f]+$/);
  assert.equal(a, b);
  assert.notEqual(a, c);
  assert.equal(responses.promptCacheKey([{ role: 'assistant', content: 'x' }]), '');
});

test('responses stream decoder handles text and reasoning', () => {
  const state = responses.newResponsesStreamState();
  let delta = responses.parseResponsesData(
    JSON.stringify({ type: 'response.output_text.delta', delta: 'Hi' }), state);
  assert.equal(delta.content, 'Hi');
  assert.equal(delta.done, false);
  delta = responses.parseResponsesData(
    JSON.stringify({ type: 'response.reasoning_summary_text.delta', delta: 'think' }), state);
  assert.equal(delta.reasoning, 'think');
  // Unknown events and blank lines are ignored without error.
  delta = responses.parseResponsesData(
    JSON.stringify({ type: 'response.created' }), state);
  assert.equal(delta.content, '');
  assert.equal(delta.error, '');
  delta = responses.parseResponsesData('   ', state);
  assert.equal(delta.done, false);
});

test('responses stream decoder assembles a tool call', () => {
  const state = responses.newResponsesStreamState();
  const added = responses.parseResponsesData(JSON.stringify({
    type: 'response.output_item.added',
    item: { id: 'fc_1', type: 'function_call', call_id: 'call_1', name: 'shell' }
  }), state);
  assert.equal(added.toolCalls.length, 1);
  assert.equal(added.toolCalls[0].index, 0);
  assert.equal(added.toolCalls[0].id, 'call_1|fc_1');
  assert.equal(added.toolCalls[0].name, 'shell');

  const args = responses.parseResponsesData(JSON.stringify({
    type: 'response.function_call_arguments.delta',
    item_id: 'fc_1',
    delta: '{"command":'
  }), state);
  assert.equal(args.toolCalls[0].index, 0);
  assert.equal(args.toolCalls[0].name, '');
  assert.equal(args.toolCalls[0].arguments, '{"command":');

  const done = responses.parseResponsesData(JSON.stringify({
    type: 'response.output_item.done',
    item: {
      id: 'fc_1', type: 'function_call', call_id: 'call_1', name: 'shell',
      arguments: '{"command":"ls"}'
    }
  }), state);
  // The name was already sent; only the missing argument suffix is replayed.
  assert.equal(done.toolCalls[0].name, '');
  assert.equal(done.toolCalls[0].arguments, '"ls"}');
  assert.equal(done.toolCalls[0].id, 'call_1|fc_1');
});

test('responses stream decoder replays args for relays that do not stream them', () => {
  const state = responses.newResponsesStreamState();
  const done = responses.parseResponsesData(JSON.stringify({
    type: 'response.output_item.done',
    item: {
      id: 'fc_2', type: 'function_call', call_id: 'call_2', name: 'read',
      arguments: '{"path":"a"}'
    }
  }), state);
  assert.equal(done.toolCalls[0].name, 'read');
  assert.equal(done.toolCalls[0].arguments, '{"path":"a"}');

  // A second item gets the next index, and its item id is not folded in twice.
  const second = responses.parseResponsesData(JSON.stringify({
    type: 'response.output_item.added',
    item: { id: 'fc_3', type: 'function_call', call_id: 'call_3', name: 'write' }
  }), state);
  assert.equal(second.toolCalls[0].index, 1);
});

test('responses completed event reports usage and finish reason', () => {
  const state = responses.newResponsesStreamState();
  responses.parseResponsesData(JSON.stringify({
    type: 'response.output_text.delta', delta: 'hello'
  }), state);
  const completed = responses.parseResponsesData(JSON.stringify({
    type: 'response.completed',
    response: { usage: { input_tokens: 10, output_tokens: 4 } }
  }), state);
  assert.equal(completed.done, true);
  assert.equal(completed.finishReason, 'stop');
  assert.equal(completed.usage.promptTokens, 10);
  assert.equal(completed.usage.completionTokens, 4);
  assert.equal(completed.usage.totalTokens, 14);
  assert.equal(completed.usage.present, true);

  // A turn that ended in tool calls reports that as the reason.
  const toolState = responses.newResponsesStreamState();
  responses.parseResponsesData(JSON.stringify({
    type: 'response.output_item.added',
    item: { id: 'fc_4', type: 'function_call', call_id: 'call_4', name: 'shell' }
  }), toolState);
  const toolDone = responses.parseResponsesData(
    JSON.stringify({ type: 'response.completed', response: {} }), toolState);
  assert.equal(toolDone.finishReason, 'tool_calls');
  // No usage block leaves zeros but still marks the turn done.
  assert.equal(toolDone.usage.present, false);
  assert.equal(toolDone.done, true);
});

test('responses failures and incomplete turns surface errors', () => {
  const state = responses.newResponsesStreamState();
  const failed = responses.parseResponsesData(JSON.stringify({
    type: 'response.failed',
    response: { error: { code: 'rate_limit', message: 'slow down' } }
  }), state);
  assert.equal(failed.error, '[rate_limit] slow down');
  assert.equal(failed.done, false);

  const errored = responses.parseResponsesData(JSON.stringify({
    type: 'error', code: 'auth', message: 'token expired'
  }), state);
  assert.equal(errored.error, '[auth] token expired');

  const nested = responses.parseResponsesData(JSON.stringify({
    type: 'error', error: { message: 'nested detail' }
  }), state);
  assert.equal(nested.error, 'nested detail');

  const unparsable = responses.parseResponsesData('{oops', state);
  assert.equal(unparsable.error, '无法解析流式响应');

  // With partial text, `incomplete` keeps it and flags `length`.
  const partial = responses.newResponsesStreamState();
  responses.parseResponsesData(JSON.stringify({
    type: 'response.output_text.delta', delta: 'half'
  }), partial);
  const cut = responses.parseResponsesData(
    JSON.stringify({ type: 'response.incomplete' }), partial);
  assert.equal(cut.done, true);
  assert.equal(cut.finishReason, 'length');
  assert.equal(cut.error, '');

  // With nothing generated, the same event is an error.
  const empty = responses.newResponsesStreamState();
  const nothing = responses.parseResponsesData(
    JSON.stringify({ type: 'response.incomplete' }), empty);
  assert.equal(nothing.error, '模型输出被截断');
});

test('responses sends [DONE] as completion', () => {
  const state = responses.newResponsesStreamState();
  const done = responses.parseResponsesData('[DONE]', state);
  assert.equal(done.done, true);
});

test('subagent progress level parsing', () => {
  assert.equal(jobs.parseProgressLevel('frequent'), 'frequent');
  assert.equal(jobs.parseProgressLevel('  MODERATE '), 'moderate');
  assert.equal(jobs.parseProgressLevel('none'), 'none');
  assert.equal(jobs.parseProgressLevel('hourly'), 'none');
  assert.equal(jobs.parseProgressLevel(''), 'none');
  assert.equal(jobs.progressInterval('frequent'), 15000);
  assert.equal(jobs.progressInterval('moderate'), 60000);
  assert.equal(jobs.progressInterval('none'), 0);
});

test('subagent progress signature tracks tool, turns and latest text', () => {
  const base = jobs.progressSignature('shell_execute', 1, 'working');
  assert.equal(base, 'shell_execute|1|working');
  assert.notEqual(base, jobs.progressSignature('read_file', 1, 'working'));
  assert.notEqual(base, jobs.progressSignature('shell_execute', 2, 'working'));
  assert.notEqual(base, jobs.progressSignature('shell_execute', 1, 'done'));
  // Only the first 200 characters matter.
  const long = 'x'.repeat(300);
  assert.equal(jobs.progressSignature('t', 1, long),
    jobs.progressSignature('t', 1, 'x'.repeat(200)));
});

test('subagent progress message summarises the run', () => {
  const record = jobs.newJobRecord('abcd1234', 'parent', 'child', '调研',
    'do it', 'gpt-5.5', 1000);
  record.state = 'running';
  const text = jobs.progressMessage(record, 'shell_execute', 80000, 3, '正在读取文件');
  assert.ok(text.startsWith('[后台任务进度 · 调研 · job_id=abcd1234]'));
  assert.ok(text.includes('状态：运行中'));
  assert.ok(text.includes('已用时'));
  assert.ok(text.includes('已进行 3 轮'));
  assert.ok(text.includes('当前工具：shell_execute'));
  assert.ok(text.includes('正在读取文件'));

  // Without a tool the line is omitted, and an empty transcript says so.
  const quiet = jobs.progressMessage(record, '', 1000, 0, '   ');
  assert.ok(!quiet.includes('当前工具'));
  assert.ok(quiet.includes('（子代理还没有输出文本）'));

  // The tail of a long message is kept, bounded to 800 characters.
  const body = 'y'.repeat(1200) + 'END';
  const long = jobs.progressMessage(record, '', 1000, 1, body);
  assert.ok(long.endsWith('END'));
  assert.ok(long.length < 1200);
  assert.ok(!long.includes('y'.repeat(801)));
});

test('subagent roster normalizes names and always keeps the built-in', () => {
  assert.deepEqual(roster.defaultAgents(), [roster.builtinAgent()]);
  assert.equal(roster.normalizeAgentName('  Research Bot! '), 'research-bot');
  assert.equal(roster.normalizeAgentName('--a__b--'), 'a__b');
  assert.equal(roster.normalizeAgentName('中文'), '');
  // Unknown input still yields a usable identifier.
  assert.equal(roster.normalizeAgentName('!!!'), '');

  const raw = [
    { id: '1', name: 'Research', description: '  finds things  ', instructions: 'be thorough', builtIn: false },
    { id: '2', name: 'research', description: 'duplicate', instructions: '', builtIn: false },
    { id: '3', name: '', description: '', instructions: '', builtIn: false },
    { id: '4', name: 'helper', description: 'fake builtin', instructions: '', builtIn: false }
  ];
  const agents = roster.normalizeAgents(raw);
  assert.equal(agents[0].name, 'helper');
  assert.equal(agents[0].builtIn, true);
  assert.equal(agents.length, 3);
  assert.equal(agents[1].name, 'research');
  assert.equal(agents[1].description, 'finds things');
  assert.equal(agents[1].instructions, 'be thorough');
  assert.equal(agents[2].name, 'agent');
  // Limits and field clamps hold for stored data.
  assert.equal(roster.normalizeAgents(undefined).length, 1);
  const many = [];
  for (let i = 0; i < 20; i++) {
    many.push({ id: 'id' + i, name: 'a' + i, description: 'd'.repeat(500), instructions: '', builtIn: false });
  }
  const clamped = roster.normalizeAgents(many);
  assert.equal(clamped.length, roster.MAX_SUB_AGENTS);
  assert.equal(clamped[1].description.length, roster.SUB_AGENT_DESCRIPTION_MAX);
  const longName = roster.normalizeAgents([
    { id: 'x', name: 'n'.repeat(80), description: '', instructions: '', builtIn: false }
  ]);
  assert.equal(longName[1].name.length, roster.SUB_AGENT_NAME_MAX);
});

test('subagent roster prompt and resolution', () => {
  // A lone built-in costs nothing in the system prompt.
  assert.equal(roster.rosterPrompt(roster.defaultAgents()), '');
  const agents = roster.normalizeAgents([
    { id: 'r', name: 'research', description: '查找资料', instructions: '先列提纲', builtIn: false }
  ]);
  const prompt = roster.rosterPrompt(agents);
  assert.ok(prompt.startsWith('## 子代理名册'));
  assert.ok(prompt.includes('- research：查找资料'));
  assert.ok(prompt.includes('不写 agent 时使用 helper'));

  assert.equal(roster.resolveAgent(agents, '').name, 'helper');
  assert.equal(roster.resolveAgent(agents, 'RESEARCH').name, 'research');
  assert.equal(roster.resolveAgent(agents, 'missing'), null);
  assert.equal(roster.agentNameList(agents), 'helper、research');

  // Custom instructions are appended to the generic child brief.
  const custom = roster.resolveAgent(agents, 'research');
  assert.ok(roster.childBrief(custom).includes('先列提纲'));
  assert.ok(roster.childBrief(custom).includes('独立的子代理'));
  assert.ok(!roster.childBrief(roster.builtinAgent()).includes('先列提纲'));
});

test('subagent child session titles carry the agent name', () => {
  assert.equal(roster.childSessionTitle('调研', 'helper'), '子代理 · 调研');
  assert.equal(roster.childSessionTitle('调研', 'research'), '子代理 · research · 调研');
  assert.equal(roster.childSessionTitle('', 'research'), '子代理 · research');
  assert.equal(roster.childSessionTitle('', 'helper'), '子代理');
});

test('i18n language normalization and locale list', () => {
  assert.equal(i18n.I18N_LANGUAGES.length, 18);
  assert.equal(i18n.normalizeI18nLanguage('zh-CN'), 'zh-Hans');
  assert.equal(i18n.normalizeI18nLanguage('zh'), 'zh-Hans');
  assert.equal(i18n.normalizeI18nLanguage('zh-Hant-TW'), 'zh-Hant');
  assert.equal(i18n.normalizeI18nLanguage('zh-TW'), 'zh-Hant');
  assert.equal(i18n.normalizeI18nLanguage('en-US'), 'en');
  assert.equal(i18n.normalizeI18nLanguage('pt-PT'), 'pt-BR');
  assert.equal(i18n.normalizeI18nLanguage('tl'), 'fil');
  assert.equal(i18n.normalizeI18nLanguage('fr-CA'), 'fr');
  assert.equal(i18n.normalizeI18nLanguage('unknown'), 'zh-Hans');
  assert.equal(i18n.i18nLanguageLabel('ja'), '日本語');
  assert.equal(i18n.i18nLanguageLabel('pt-BR'), 'Português (Brasil)');
});

test('i18n catalogs fall back through English to the source string', () => {
  i18n.registerI18nCatalog('en', { '保存': 'Save', '设置': 'Settings' });
  i18n.registerI18nCatalog('ja', { '保存': '保存する' });
  i18n.selectI18nLanguage('ja');
  assert.equal(i18n.t('保存'), '保存する');
  assert.equal(i18n.t('设置'), 'Settings');
  assert.equal(i18n.t('未知文本'), '未知文本');
  assert.deepEqual(i18n.i18nVariants('保存'), ['保存', 'Save', '保存する']);
  assert.deepEqual(i18n.i18nVariants('未知文本'), ['未知文本']);
  assert.equal(i18n.activeI18nLanguage(), 'ja');
  i18n.selectI18nLanguage('zh-Hans');
  assert.equal(i18n.t('保存'), '保存');
  assert.equal(i18n.activeI18nLanguage(), 'zh-Hans');
});

test('prompt queue is FIFO and drops only injected entries', () => {
  const first = new promptQueue.QueuedPrompt('first', [], 's1');
  const second = new promptQueue.QueuedPrompt('second', [], 's1');
  const original = [];
  const one = promptQueue.enqueueQueued(original, first);
  const two = promptQueue.enqueueQueued(one, second);
  assert.equal(original.length, 0, 'enqueue does not mutate its input');
  assert.deepEqual(two.map((item) => item.text), ['first', 'second']);

  assert.equal(promptQueue.dropQueued(two, 0), two, 'zero drop is a no-op');
  assert.equal(promptQueue.dropQueued(two, -1), two, 'negative drop is a no-op');
  assert.deepEqual(promptQueue.dropQueued(two, 1).map((item) => item.text), ['second']);
  assert.deepEqual(promptQueue.dropQueued(two, 9), [], 'over-drop clamps to empty');
  assert.equal(two.length, 2, 'drops are copies');
});

test('queued prompt turns attachments into image parts in order', () => {
  const item = new promptQueue.QueuedPrompt('look', [
    { uri: 'attachment:a.png', mimeType: 'image/png', path: '/s/a.png' },
    { uri: 'attachment:b.jpg', mimeType: 'image/jpeg', path: '/s/b.jpg' }
  ], 's1');
  const parts = promptQueue.queuedParts(item);
  assert.equal(parts.length, 2);
  assert.deepEqual(parts.map((part) => part.uri), ['attachment:a.png', 'attachment:b.jpg']);
  assert.deepEqual(parts.map((part) => part.mimeType), ['image/png', 'image/jpeg']);
  assert.equal(promptQueue.queuedParts(new promptQueue.QueuedPrompt('t', [], 's1')).length, 0);
});

test('session folders normalize, add, rename, collapse and remove immutably', () => {
  const normalized = types.normalizeSessionFolders([
    { id: ' a ', name: ' Work ', collapsed: true },
    { id: 'a', name: 'duplicate', collapsed: false },
    { id: '', name: 'no id', collapsed: false },
    { id: 'b', name: '   ', collapsed: false }
  ]);
  assert.deepEqual(normalized, [{ id: 'a', name: 'Work', collapsed: true }]);
  assert.deepEqual(types.normalizeSessionFolders(undefined), []);

  const base = [];
  const added = folders.addFolder(base, ' 项目 ', 'folder-1');
  assert.deepEqual(added, [{ id: 'folder-1', name: '项目', collapsed: false }]);
  assert.equal(base.length, 0, 'add does not mutate');
  assert.equal(folders.addFolder(added, '   ', 'folder-2'), added, 'empty name rejected');
  assert.equal(folders.addFolder(added, 'dup', 'folder-1'), added, 'duplicate id rejected');

  const renamed = folders.renameFolder(added, 'folder-1', ' 归档 ');
  assert.equal(renamed[0].name, '归档');
  assert.equal(added[0].name, '项目');
  assert.equal(folders.renameFolder(added, 'folder-1', '  '), added, 'empty rename rejected');

  const collapsed = folders.setFolderCollapsed(renamed, 'folder-1', true);
  assert.equal(collapsed[0].collapsed, true);
  assert.equal(renamed[0].collapsed, false);

  assert.deepEqual(folders.removeFolder(collapsed, 'folder-1'), []);
  assert.deepEqual(folders.removeFolder(collapsed, 'missing').length, 1);
  assert.equal(folders.findFolder(collapsed, 'folder-1').name, '归档');
  assert.equal(folders.findFolder(collapsed, 'missing'), null);
});

test('new folder ids avoid collisions', () => {
  const now = 1700000000000;
  const first = folders.newFolderId([], now);
  const taken = [{ id: first, name: 'one', collapsed: false }];
  const second = folders.newFolderId(taken, now);
  assert.notEqual(second, first);
  assert.equal(second.startsWith(first + '-'), true);
});

test('folder grouping keeps folder order, empties and the ungrouped bucket', () => {
  const make = (id, folderId) => ({
    id, title: id, updatedAt: 0, modelId: 'm', messageCount: 0,
    pinned: false, archived: false, folderId
  });
  const metas = [
    make('s1', 'f1'),
    make('s2', undefined),
    make('s3', 'f2'),
    make('s4', 'deleted-folder'),
    make('s5', 'f1')
  ];
  const list = [
    { id: 'f1', name: 'One', collapsed: false },
    { id: 'f2', name: 'Two', collapsed: true },
    { id: 'f3', name: 'Empty', collapsed: false }
  ];
  const groups = folders.groupByFolder(metas, list);
  assert.deepEqual(groups.map((group) => group.id), ['f1', 'f2', 'f3', '']);
  assert.deepEqual(groups[0].sessions.map((item) => item.id), ['s1', 's5']);
  assert.deepEqual(groups[1].sessions.map((item) => item.id), ['s3']);
  assert.equal(groups[1].collapsed, true);
  assert.equal(groups[2].sessions.length, 0);
  assert.deepEqual(groups[3].sessions.map((item) => item.id), ['s2', 's4']);
  assert.equal(groups[3].label, '');
  assert.equal(folders.countFolderSessions(metas, 'f1'), 2);
  assert.equal(folders.countFolderSessions(metas, ''), 1, 'only truly unassigned sessions count');

  const noUngrouped = folders.groupByFolder([make('s1', 'f1')], list);
  assert.equal(noUngrouped.length, 3);
  assert.equal(noUngrouped[2].id, 'f3');
});

test('browser history parses defensively and keeps web URLs only', () => {
  assert.deepEqual(browserHistory.parseHistory(''), []);
  assert.deepEqual(browserHistory.parseHistory('not json'), []);
  assert.deepEqual(browserHistory.parseHistory('{"url":"https://a"}'), []);
  const parsed = browserHistory.parseHistory(JSON.stringify([
    { url: 'https://a.com', title: 'A', at: 5 },
    { url: 'file:///etc/passwd', title: 'bad', at: 1 },
    { url: 'https://b.com', at: 'bad' },
    { url: 3 }
  ]));
  assert.deepEqual(parsed.map((item) => item.url), ['https://a.com', 'https://b.com']);
  assert.equal(parsed[0].title, 'A');
  assert.equal(parsed[1].title, '');
  assert.equal(parsed[1].at, 0);
});

test('browser history dedupes by URL and keeps newest first', () => {
  const first = browserHistory.recordHistory([], {
    url: 'https://a.com', title: 'A', at: 1
  });
  const second = browserHistory.recordHistory(first, {
    url: 'https://b.com', title: 'B', at: 2
  });
  const revisit = browserHistory.recordHistory(second, {
    url: 'https://a.com', title: 'A2', at: 3
  });
  assert.deepEqual(revisit.map((item) => item.url), ['https://a.com', 'https://b.com']);
  assert.equal(revisit[0].title, 'A2');
  assert.equal(revisit[0].at, 3);
  const untitled = browserHistory.recordHistory(revisit, {
    url: 'https://c.com', title: '', at: 4
  });
  assert.equal(untitled[0].title, 'https://c.com');
  assert.equal(browserHistory.recordHistory(second, {
    url: 'data:text/html,hi', title: 'x', at: 5
  }), second, 'non-web URLs are ignored');
  const capped = browserHistory.recordHistory(second, {
    url: 'https://c.com', title: 'C', at: 3
  }, 2);
  assert.equal(capped.length, 2);
});

test('browser history search matches title and URL case-insensitively', () => {
  const list = [
    { url: 'https://Example.com/docs', title: 'Harmony Docs', at: 1 },
    { url: 'https://other.org', title: 'News', at: 2 }
  ];
  assert.deepEqual(browserHistory.filterHistory(list, ' ').map((item) => item.url),
    ['https://Example.com/docs', 'https://other.org']);
  assert.deepEqual(browserHistory.filterHistory(list, 'DOC').map((item) => item.url),
    ['https://Example.com/docs']);
  assert.deepEqual(browserHistory.filterHistory(list, 'other').map((item) => item.url),
    ['https://other.org']);
  assert.deepEqual(browserHistory.filterHistory(list, 'missing'), []);
});

test('browser downloads parse and upsert by path', () => {
  assert.deepEqual(browserHistory.parseDownloads('[]'), []);
  const parsed = browserHistory.parseDownloads(JSON.stringify([
    { name: 'a.pdf', path: '/d/a.pdf', at: 4, bytes: 12, ok: true },
    { path: '' },
    { name: 'b.pdf' }
  ]));
  assert.equal(parsed.length, 1);
  assert.equal(parsed[0].bytes, 12);
  const one = browserHistory.upsertDownload([], {
    name: 'a.pdf', path: '/d/a.pdf', at: 1, bytes: 0, ok: false
  });
  const two = browserHistory.upsertDownload(one, {
    name: 'b.pdf', path: '/d/b.pdf', at: 2, bytes: 3, ok: true
  });
  const updated = browserHistory.upsertDownload(two, {
    name: 'a.pdf', path: '/d/a.pdf', at: 3, bytes: 9, ok: true
  });
  assert.deepEqual(updated.map((item) => item.name), ['a.pdf', 'b.pdf']);
  assert.equal(updated[0].ok, true);
  assert.equal(updated[0].bytes, 9);
});

test('browser download sizes format compactly', () => {
  assert.equal(browserHistory.formatBytes(0), '—');
  assert.equal(browserHistory.formatBytes(512), '512 B');
  assert.equal(browserHistory.formatBytes(2048), '2.0 KB');
  assert.equal(browserHistory.formatBytes(5 * 1024 * 1024), '5.0 MB');
});

test('cookie origins dedupe current page and history', () => {
  assert.equal(browserHistory.webOrigin('https://example.com/a/b?q=1#x'),
    'https://example.com');
  assert.equal(browserHistory.webOrigin('http://localhost:8080/'), 'http://localhost:8080');
  assert.equal(browserHistory.webOrigin('file:///tmp/a.html'), '');
  assert.equal(browserHistory.webOrigin('https://example.com'), 'https://example.com');
  const history = [
    { url: 'https://a.test/x', title: '', at: 1 },
    { url: 'https://b.test:8443/y', title: '', at: 2 },
    { url: 'https://a.test/z', title: '', at: 3 },
    { url: 'file:///local', title: '', at: 4 }
  ];
  assert.deepEqual(
    browserHistory.cookieOrigins(history, 'https://c.test/start', 10),
    ['https://c.test', 'https://a.test', 'https://b.test:8443']);
  assert.deepEqual(
    browserHistory.cookieOrigins(history, 'https://a.test/page', 10),
    ['https://a.test', 'https://b.test:8443']);
  assert.deepEqual(browserHistory.cookieOrigins(history, '', 2),
    ['https://a.test', 'https://b.test:8443']);
});

function titleMessage(role, text, error = false) {
  return {
    id: role + '-' + text.length,
    role,
    parts: [{ kind: 'text', text }],
    createdAt: 0,
    error
  };
}

test('session titles clean wrappers, prefixes and length', () => {
  assert.equal(sessionTitle.cleanTitle('「重构 侧栏 分组。」'), '重构 侧栏 分组');
  assert.equal(sessionTitle.cleanTitle('标题：修复登录问题'), '修复登录问题');
  assert.equal(sessionTitle.cleanTitle('Title: Browser history'), 'Browser history');
  assert.equal(sessionTitle.cleanTitle('  \n   '), '');
  assert.equal(sessionTitle.cleanTitle('hello\nsecond line'), 'hello');
  const long = sessionTitle.cleanTitle('一'.repeat(30));
  assert.equal(long.length, 21);
  assert.equal(long.endsWith('…'), true);
  assert.equal(sessionTitle.collapseSpaces('  a \n\t b  '), 'a b');
});

test('title transcript keeps the first exchange and a long tail', () => {
  assert.equal(sessionTitle.titleTranscript([]), '');
  const onlyUser = [titleMessage('user', '写一个测试')];
  assert.equal(sessionTitle.titleTranscript(onlyUser), '用户：写一个测试');
  assert.equal(sessionTitle.hasAnswer(onlyUser), false);
  const pair = [
    titleMessage('user', '帮我整理浏览器历史'),
    titleMessage('assistant', '可以，先打开历史面板'),
    titleMessage('user', '再来一步'),
    titleMessage('assistant', '已完成')
  ];
  assert.equal(sessionTitle.hasAnswer(pair), true);
  assert.equal(sessionTitle.firstUserText(pair), '帮我整理浏览器历史');
  assert.equal(sessionTitle.firstAssistantText(pair), '可以，先打开历史面板');
  const transcript = sessionTitle.titleTranscript(pair);
  assert.equal(transcript.includes('用户：帮我整理浏览器历史'), true);
  assert.equal(transcript.includes('助手：可以，先打开历史面板'), true);
  assert.equal(transcript.includes('再来一步'), false, 'short chats omit the tail');

  const long = [];
  for (let i = 0; i < 5; i++) {
    long.push(titleMessage('user', '问题' + i));
    long.push(titleMessage('assistant', '回答' + i));
  }
  const longTranscript = sessionTitle.titleTranscript(long);
  assert.equal(longTranscript.includes('最近助手：回答4'), true);
  assert.equal(longTranscript.includes('最近助手：回答0'), false);
});

test('title suggestions parse an offered folder and reject invented ones', () => {
  const folders = ['工作', 'Learning'];
  const picked = sessionTitle.parseTitleSuggestion(
    '{"title":"修复登录问题","folder":"工作"}', folders);
  assert.equal(picked.title, '修复登录问题');
  assert.equal(picked.folder, '工作');
  const caseInsensitive = sessionTitle.parseTitleSuggestion(
    '```json\n{"title":"Fix login","folder":"learning"}\n```', folders);
  assert.equal(caseInsensitive.title, 'Fix login');
  assert.equal(caseInsensitive.folder, 'Learning');
  const invented = sessionTitle.parseTitleSuggestion(
    '{"title":"新项目","folder":"不存在"}', folders);
  assert.equal(invented.folder, '');
  assert.equal(sessionTitle.parseTitleSuggestion(
    '{"title":"无分组","folder":null}', folders).folder, '');
  assert.equal(sessionTitle.parseTitleSuggestion(
    '{"title":"无分组"}', folders).folder, '');
  assert.equal(sessionTitle.parseTitleSuggestion(
    '{"title":""}', folders).title, '');
  assert.equal(sessionTitle.parseTitleSuggestion('普通标题', folders).title, '普通标题');
  assert.equal(sessionTitle.parseTitleSuggestion('{"broken":', folders).title, '');
});

test('failed assistant turns do not count as an answer', () => {
  const messages = [
    titleMessage('user', '你好'),
    titleMessage('assistant', '出错了', true)
  ];
  assert.equal(sessionTitle.hasAnswer(messages), false);
  assert.equal(sessionTitle.titleTranscript(messages), '用户：你好');
});

test('mention trigger only fires on a trailing token', () => {
  assert.deepEqual(mention.activeMention('看看 @src/ma'), { start: 3, query: 'src/ma' });
  assert.deepEqual(mention.activeMention('@'), { start: 0, query: '' });
  assert.deepEqual(mention.activeMention('问一下\n@a.md'), { start: 4, query: 'a.md' });
  assert.equal(mention.activeMention('mail me at a@b.com'), null,
    'email-style @ is not a mention');
  assert.equal(mention.activeMention('@src/ma 后面的字'), null,
    'whitespace ends the token');
  assert.equal(mention.activeMention('没有 at'), null);
});

test('mention replacement keeps surrounding text', () => {
  assert.equal(mention.replaceMention('看看 @src/ma', 3, 'src/main.ets'),
    '看看 @src/main.ets ');
  assert.equal(mention.replaceMention('@x', 0, 'a.md'), '@a.md ');
  assert.equal(mention.replaceMention('abc', 99, 'a.md'), 'abc@a.md ',
    'out-of-range start falls back to the end');
});

test('mention filtering skips dirs and matches paths case-insensitively', () => {
  const entries = [
    { name: 'src', path: 'src', isDir: true, size: 0 },
    { name: 'Main.ets', path: 'src/Main.ets', isDir: false, size: 10 },
    { name: 'readme.md', path: 'readme.md', isDir: false, size: 4 }
  ];
  assert.deepEqual(mention.filterMentionFiles(entries, '', 10).map((e) => e.path),
    ['src/Main.ets', 'readme.md']);
  assert.deepEqual(mention.filterMentionFiles(entries, 'main', 10).map((e) => e.path),
    ['src/Main.ets']);
  assert.deepEqual(mention.filterMentionFiles(entries, 'SRC/', 10).map((e) => e.path),
    ['src/Main.ets']);
  assert.equal(mention.filterMentionFiles(entries, '', 1).length, 1);
});

test('dayKey follows the local calendar', () => {
  assert.equal(usageStats.dayKey(new Date(2026, 0, 5, 23, 59).getTime()), '2026-01-05');
  assert.equal(usageStats.dayKey(new Date(2026, 10, 9, 0, 0).getTime()), '2026-11-09');
});

test('parseUsage drops junk and normalizes counts', () => {
  assert.deepEqual(usageStats.parseUsage(''), []);
  assert.deepEqual(usageStats.parseUsage('not json'), []);
  assert.deepEqual(usageStats.parseUsage('{"date":"2026-01-01"}'), []);
  const raw = JSON.stringify([
    { date: '2026-01-01', model: ' gpt-5 ', preset: 'fast',
      prompt: 10.9, completion: 4, requests: 2 },
    { date: '2026-01-01', model: '', prompt: 1, completion: 1 },
    { date: 'bad', model: 'x', prompt: 1, completion: 1 },
    { date: '2026-01-02', model: 'claude', prompt: -5, completion: 'x' }
  ]);
  const parsed = usageStats.parseUsage(raw);
  assert.equal(parsed.length, 2);
  assert.deepEqual(parsed[0], {
    date: '2026-01-01', model: 'gpt-5', preset: 'fast',
    prompt: 10, completion: 4, requests: 2
  });
  assert.deepEqual(parsed[1], {
    date: '2026-01-02', model: 'claude', preset: '',
    prompt: 0, completion: 0, requests: 0
  });
});

test('recordUsage merges the same day/model/preset row', () => {
  const first = usageStats.recordUsage([], '2026-01-01', 'gpt-5', 'fast', 10, 5);
  assert.deepEqual(first, [{
    date: '2026-01-01', model: 'gpt-5', preset: 'fast',
    prompt: 10, completion: 5, requests: 1
  }]);
  const second = usageStats.recordUsage(first, '2026-01-01', 'gpt-5', 'fast', 2, 3);
  assert.equal(second.length, 1);
  assert.deepEqual(second[0], {
    date: '2026-01-01', model: 'gpt-5', preset: 'fast',
    prompt: 12, completion: 8, requests: 2
  });
  const other = usageStats.recordUsage(second, '2026-01-01', 'gpt-5', 'deep', 1, 1);
  assert.equal(other.length, 2, 'a preset change starts a new row');
  assert.equal(usageStats.recordUsage(other, '', 'x', '', 1, 1).length, 2,
    'an empty date is ignored');
});

test('recordUsage caps the history at the newest rows', () => {
  let records = [];
  const limit = usageStats.USAGE_RECORD_LIMIT;
  for (let i = 0; i < limit + 5; i++) {
    const day = new Date(Date.UTC(2026, 0, 1 + i)).toISOString().slice(0, 10);
    records = usageStats.recordUsage(records, day, 'm' + i.toString(), '', 1, 1);
  }
  assert.equal(records.length, limit);
  assert.equal(records.some((row) => row.model === 'm0'), false,
    'oldest rows fall off first');
  assert.equal(records.some((row) => row.model === 'm' + (limit + 4).toString()), true);
});

test('usage rollups total by model and by day', () => {
  const records = [
    { date: '2026-01-01', model: 'a', preset: '', prompt: 10, completion: 5, requests: 1 },
    { date: '2026-01-02', model: 'a', preset: 'fast', prompt: 20, completion: 1, requests: 2 },
    { date: '2026-01-02', model: 'b', preset: '', prompt: 3, completion: 4, requests: 1 }
  ];
  assert.deepEqual(usageStats.usageTotal(records),
    { prompt: 33, completion: 10, requests: 4 });
  const byModel = usageStats.usageByModel(records);
  assert.deepEqual(byModel.map((row) => row.model), ['a', 'b']);
  assert.deepEqual(byModel[0],
    { model: 'a', prompt: 30, completion: 6, requests: 3 });
  const byDay = usageStats.usageByDay(records, 7);
  assert.deepEqual(byDay.map((row) => row.date), ['2026-01-02', '2026-01-01']);
  assert.deepEqual(byDay[0],
    { date: '2026-01-02', prompt: 23, completion: 5, requests: 3 });
  assert.equal(usageStats.usageByDay(records, 1).length, 1);
  assert.equal(usageStats.usageByDay(records, 0).length, 2,
    'a zero limit keeps every day');
  const byProvider = usageStats.usageByProvider(records);
  assert.deepEqual(byProvider.map((row) => row.preset), ['', 'fast']);
  assert.deepEqual(byProvider[0],
    { preset: '', prompt: 13, completion: 9, requests: 2 });
  assert.deepEqual(byProvider[1],
    { preset: 'fast', prompt: 20, completion: 1, requests: 2 });
  assert.deepEqual(usageStats.usageByProvider([]), []);
});

test('MCP session overrides normalize and toggle one server', () => {
  assert.deepEqual(mcpOverrides.normalizeMcpDisabled([' a ', '', 'b', 'a']), ['a', 'b']);
  assert.equal(mcpOverrides.isMcpDisabled(['a', 'b'], 'b'), true);
  assert.equal(mcpOverrides.isMcpDisabled(['a'], 'z'), false);
  assert.deepEqual(mcpOverrides.setMcpDisabled(['a'], 'b', true), ['a', 'b']);
  assert.deepEqual(mcpOverrides.setMcpDisabled(['a', 'b'], 'a', true), ['b', 'a'],
    'turning an already-disabled server off keeps it last');
  assert.deepEqual(mcpOverrides.setMcpDisabled(['a', 'b'], 'a', false), ['b']);
  assert.deepEqual(mcpOverrides.setMcpDisabled(['a'], '  ', true), ['a'],
    'an empty id changes nothing');
  assert.deepEqual(mcpOverrides.normalizeMcpEnabled([' a ', '', 'b', 'a']), ['a', 'b']);
  assert.equal(mcpOverrides.isMcpEnabled(['a'], 'a'), true);
  assert.deepEqual(mcpOverrides.setMcpEnabled(['a'], 'b', true), ['a', 'b']);
  assert.deepEqual(mcpOverrides.setMcpEnabled(['a', 'b'], 'a', false), ['b']);
  assert.equal(mcpOverrides.mcpServerActive(true, [], [], 's'), true);
  assert.equal(mcpOverrides.mcpServerActive(true, ['s'], ['s'], 's'), false,
    'a session-off global server stays off');
  assert.equal(mcpOverrides.mcpServerActive(false, [], [], 's'), false);
  assert.equal(mcpOverrides.mcpServerActive(false, [], ['s'], 's'), true,
    'force-enable only matters for globally disabled servers');
});

test('model quick test line formats failure, empty reply and latency', () => {
  assert.equal(modelTest.modelTestLine(
    { ok: false, text: '', message: 'HTTP 401', elapsedMs: 120 }), 'HTTP 401');
  assert.equal(modelTest.modelTestLine(
    { ok: false, text: '', message: '', elapsedMs: 120 }), '模型测试失败');
  assert.equal(modelTest.modelTestLine(
    { ok: true, text: '   ', message: '', elapsedMs: 90 }), '模型没有返回内容');
  assert.equal(modelTest.modelTestLine(
    { ok: true, text: 'OK', message: '', elapsedMs: 321 }), '321 ms · OK');
  assert.equal(modelTest.modelTestLine(
    { ok: true, text: 'a\nb\tc', message: '', elapsedMs: 5 }), '5 ms · a b c');
  const long = 'x'.repeat(120);
  const line = modelTest.modelTestLine(
    { ok: true, text: long, message: '', elapsedMs: 7 });
  assert.equal(line, '7 ms · ' + 'x'.repeat(80) + '…');
  assert.equal(line.endsWith('…'), true);
  // An image test never has text; the line reports the generated image.
  assert.equal(modelTest.modelTestLine(
    { ok: true, text: '', message: '', elapsedMs: 42, imageUri: 'attachment:a.png' }),
  '42 ms · 图像已生成');
  assert.equal(modelTest.modelTestLine(
    { ok: false, text: '', message: 'HTTP 400', elapsedMs: 9, imageUri: 'attachment:a.png' }),
  'HTTP 400');
});

test('config audit diffs changed keys and keeps secrets opaque', () => {
  const before = [
    { key: 'temperature', value: '1' },
    { key: 'modelId', value: '"a"' },
    { key: 'apiKey', value: configAudit.secretConfigValue(false) },
    { key: 'mcpServers', value: configAudit.complexConfigValue(1) }
  ];
  const after = [
    { key: 'temperature', value: '0.5' },
    { key: 'modelId', value: '"a"' },
    { key: 'apiKey', value: configAudit.secretConfigValue(true) },
    { key: 'mcpServers', value: configAudit.complexConfigValue(2) }
  ];
  const entries = configAudit.diffConfig(before, after, 1000, 'user');
  assert.deepEqual(entries.map((row) => row.key),
    ['temperature', 'apiKey', 'mcpServers']);
  assert.equal(entries[0].before, '1');
  assert.equal(entries[0].after, '0.5');
  assert.equal(entries[0].restorable, true);
  assert.equal(entries[1].restorable, false, 'secrets cannot be restored');
  assert.equal(entries[2].restorable, false, 'structured values cannot be restored');
  assert.equal(entries[0].id, '1000-0-temperature');
  assert.equal(configAudit.diffConfig(before, before, 1000, 'user').length, 0);
});

test('config audit merges newest first and caps the list', () => {
  const existing = [
    { id: '3', at: 3, actor: 'user', key: 'a', before: '"x"', after: '"y"', restorable: true },
    { id: '2', at: 2, actor: 'user', key: 'b', before: '"x"', after: '"y"', restorable: true }
  ];
  const added = [
    { id: '4', at: 4, actor: 'user', key: 'c', before: '"x"', after: '"y"', restorable: true }
  ];
  const merged = configAudit.mergeConfigAudit(existing, added, 2);
  assert.deepEqual(merged.map((row) => row.id), ['4', '3']);
  assert.equal(configAudit.mergeConfigAudit([], added, 0).length, 1);
});

test('config audit parses valid rows and drops junk', () => {
  assert.deepEqual(configAudit.parseConfigAudit(''), []);
  assert.deepEqual(configAudit.parseConfigAudit('not json'), []);
  const raw = JSON.stringify([
    { id: '1', at: 5, actor: 'user', key: 'temperature', before: '1', after: '0.5', restorable: true },
    { at: 0, key: 'broken' },
    { id: '2', at: 6, key: 'apiKey', before: '""', after: '"set"' }
  ]);
  const rows = configAudit.parseConfigAudit(raw);
  assert.equal(rows.length, 2);
  assert.equal(rows[1].key, 'apiKey');
  assert.equal(rows[1].restorable, false, 'missing restorable defaults to false');
  assert.equal(rows[1].actor, 'user');
});

test('config audit labels hide secret values and summarize lists', () => {
  assert.equal(configAudit.auditValueLabel('apiKey', '"set"'), '已设置');
  assert.equal(configAudit.auditValueLabel('apiKey', '""'), '未设置');
  assert.equal(configAudit.auditValueLabel('disabledTools', '["a","b"]'), '2 项');
  assert.equal(configAudit.auditValueLabel('temperature', '0.5'), '0.5');
  assert.equal(configAudit.auditValueLabel('systemPrompt', '""'), '（空）');
  assert.equal(configAudit.auditValueLabel('systemPrompt', JSON.stringify('a\nb')), 'a b');
  assert.equal(configAudit.auditValueLabel('systemPrompt',
    JSON.stringify('x'.repeat(60))), 'x'.repeat(48) + '…');
  assert.equal(configAudit.auditValueLabel('mcpServers',
    configAudit.complexConfigValue(3)), '3 项');
  assert.equal(configAudit.configAuditRestorable('temperature'), true);
  assert.equal(configAudit.configAuditRestorable('apiKey'), false);
  assert.equal(configAudit.configAuditRestorable('unknown'), false);
});

test('huge paste detection extracts only the inserted chunk', () => {
  const big = 'x'.repeat(paste.PASTE_FILE_THRESHOLD + 1);
  assert.equal(paste.hugePasteInsertion('', big), big);
  assert.equal(paste.hugePasteInsertion('hello', 'hello' + big), big);
  assert.equal(paste.hugePasteInsertion('hello', big + 'hello'), big);
  assert.equal(paste.hugePasteInsertion('ab', 'a' + big + 'b'), big);
  assert.equal(paste.hugePasteInsertion('notes', 'notes'), '');
  assert.equal(paste.hugePasteInsertion('a', 'a' + 'x'.repeat(100)), '');
  assert.equal(paste.hugePasteInsertion('old', big), '', 'delta below threshold');
  assert.equal(paste.hugePasteInsertion('old', big + 'zzz'), big + 'zzz',
    'replacement paste');
});

test('paste files use a stable local name and workspace path', () => {
  const at = new Date(2026, 10, 10, 9, 5, 7, 42);
  assert.equal(paste.pasteFileName(at), 'Pasted_2026-11-10_090507042.txt');
  assert.equal(paste.pastedRelativePath('Pasted_1.txt'), 'pasted/Pasted_1.txt');
  assert.equal(paste.pasteRelativePath('minis://workspace/pasted/Pasted_1.txt'),
    'pasted/Pasted_1.txt');
  assert.equal(paste.pasteRelativePath('minis://workspace/notes/a.txt'), '');
  assert.equal(paste.pasteRelativePath('minis://attachments/pasted/a.txt'), '');
  assert.equal(paste.pasteRelativePath('not a uri'), '');
  assert.equal(paste.isPastedAttachment('minis://workspace/pasted/a.txt', 'text/plain'),
    true);
  assert.equal(paste.isPastedAttachment('minis://workspace/pasted/a.txt', 'image/png'),
    false);
  assert.equal(paste.pastePlaceholder('pasted/a.txt').indexOf('pasted/a.txt') > 0, true);
});

test('agent config whitelist excludes credentials and control surfaces', () => {
  for (const key of ['temperature', 'maxTokens', 'thinkingLevel', 'enterToSend',
    'autoExpandThinking', 'autoFocusInput', 'autoTitleEnabled',
    'autoGroupingEnabled', 'fontScale', 'messageFontScale', 'inputFontScale',
    'accentColor']) {
    assert.equal(agentConfig.agentConfigKeyAllowed(key), true, key);
  }
  for (const key of ['apiKey', 'baseUrl', 'modelId', 'systemPrompt',
    'toolsEnabled', 'disabledTools', 'mcpServers', 'skills', 'webdavUrl',
    'sandboxToken', '']) {
    assert.equal(agentConfig.agentConfigKeyAllowed(key), false, key);
  }
});

test('agent config snapshot lists writable values only', () => {
  const settings = types.defaultSettings();
  settings.apiKey = 'sk-secret';
  settings.temperature = 0.4;
  settings.thinkingLevel = 'high';
  settings.enterToSend = false;
  const snapshot = agentConfig.agentConfigSnapshot(settings);
  assert.equal(snapshot.indexOf('temperature = 0.4') >= 0, true);
  assert.equal(snapshot.indexOf('thinkingLevel = high') >= 0, true);
  assert.equal(snapshot.indexOf('enterToSend = false') >= 0, true);
  assert.equal(snapshot.indexOf('sk-secret'), -1);
  assert.equal(snapshot.split('\n').length, agentConfig.AGENT_CONFIG_KEYS.length);
  assert.equal(agentConfig.agentConfigValue(settings, 'fontScale'), '1');
  assert.equal(agentConfig.agentConfigValue(settings, 'missing'), '');
});

test('agent config applies valid values on a clone', () => {
  const settings = types.defaultSettings();
  const before = settings.temperature;
  const temp = agentConfig.applyAgentConfig(settings, 'temperature', ' 0.7 ');
  assert.equal(temp.ok, true);
  assert.equal(temp.changed, true);
  assert.equal(temp.settings.temperature, 0.7);
  assert.equal(settings.temperature, before, 'original object untouched');
  assert.equal(temp.settings === settings, false);
  assert.equal(temp.message, '已更新配置：temperature = 0.7');

  const level = agentConfig.applyAgentConfig(settings, 'thinkingLevel', 'medium');
  assert.equal(level.ok, true);
  assert.equal(level.settings.thinkingLevel, 'medium');

  const tokens = agentConfig.applyAgentConfig(settings, 'maxTokens', '4096');
  assert.equal(tokens.settings.maxTokens, 4096);

  const flag = agentConfig.applyAgentConfig(settings, 'autoTitleEnabled', 'false');
  assert.equal(flag.ok, true);
  assert.equal(flag.settings.autoTitleEnabled, false);

  const scale = agentConfig.applyAgentConfig(settings, 'inputFontScale', '1.2');
  assert.equal(scale.settings.inputFontScale, 1.2);

  const accent = agentConfig.applyAgentConfig(settings, 'accentColor', '#AbCdEf');
  assert.equal(accent.ok, true);
  assert.equal(accent.settings.accentColor, '#AbCdEf');
});

test('agent config rejects bad values without touching settings', () => {
  const settings = types.defaultSettings();
  const cases = [
    ['temperature', '2.5', '温度需要 0–2 之间的数字。'],
    ['temperature', 'abc', '温度需要 0–2 之间的数字。'],
    ['maxTokens', '0', '最大输出需要 1–1000000 之间的整数。'],
    ['maxTokens', '10.5', '最大输出需要 1–1000000 之间的整数。'],
    ['thinkingLevel', 'max', '思考级别只能是 off、low、medium 或 high。'],
    ['enterToSend', 'yes', '这个配置项需要 true 或 false。'],
    ['fontScale', '0.5', '字号需要 0.9–1.3 之间的数字。'],
    ['messageFontScale', '2', '字号需要 0.9–1.3 之间的数字。'],
    ['accentColor', '#FFF', '强调色需要 #RRGGBB 格式。'],
    ['apiKey', 'sk-x', '这个配置项不允许由代理修改：apiKey'],
    ['temperature', '  ', '配置值不能为空。']
  ];
  for (const [key, value, message] of cases) {
    const outcome = agentConfig.applyAgentConfig(settings, key, value);
    assert.equal(outcome.ok, false, key + '=' + value);
    assert.equal(outcome.changed, false);
    assert.equal(outcome.settings, settings);
    assert.equal(outcome.message, message);
  }
  assert.equal(settings.apiKey, types.defaultSettings().apiKey);
});

test('agent config reports unchanged values without a rewrite', () => {
  const settings = types.defaultSettings();
  const same = agentConfig.applyAgentConfig(settings, 'temperature',
    String(settings.temperature));
  assert.equal(same.ok, true);
  assert.equal(same.changed, false);
  assert.equal(same.message, '配置未变化：temperature');
});

test('mention trigger follows the caret, not just the draft end', () => {
  const text = '看看 @src/ma 后面的字';
  assert.deepEqual(mention.activeMentionAt(text, 10), { start: 3, query: 'src/ma' },
    'caret at the end of the token mid-draft');
  assert.deepEqual(mention.activeMentionAt(text, 7), { start: 3, query: 'src' },
    'caret inside the query');
  assert.equal(mention.activeMentionAt(text, 3), null, 'caret before the @');
  assert.equal(mention.activeMentionAt(text, 2), null);
  assert.deepEqual(mention.activeMentionAt('@', 1), { start: 0, query: '' });
  assert.equal(mention.activeMentionAt('@', 0), null, 'caret before the @');
  assert.equal(mention.activeMentionAt('@', -5), null,
    'negative caret clamps to zero');
  assert.equal(mention.activeMentionAt(text, 999), null,
    'out-of-range caret clamps to the draft end');
  assert.equal(mention.activeMentionAt('mail me at a@b.com', 19), null,
    'email-style @ still ignored');
  assert.equal(mention.activeMentionAt('@src/ma 后面的字', 9), null,
    'whitespace between @ and caret ends the token');
});

test('mention replacement keeps text after the caret', () => {
  const text = '看看 @src/ma 后面的字';
  assert.equal(mention.replaceMentionRange(text, 3, 10, 'src/main.ets'),
    '看看 @src/main.ets 后面的字', 'mid-draft replacement keeps the suffix');
  assert.equal(mention.replaceMentionRange(text, 3, 10, 'a.md'),
    '看看 @a.md 后面的字', 'one existing space is absorbed');
  assert.equal(mention.replaceMentionRange('@x', 0, 2, 'a.md'), '@a.md ');
  assert.equal(mention.replaceMentionRange('abc', 99, 99, 'a.md'), 'abc@a.md ',
    'out-of-range start falls back to the end');
  assert.equal(mention.replaceMentionRange('abc', 0, 99, 'a.md'), '@a.md ',
    'out-of-range end clamps to the text length');
});
