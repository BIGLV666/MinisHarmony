import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { AppSettings, ChatMessage, PART_IMAGE } from '../core/Types';
import { claudeOAuthRequestHeaders } from './OAuth';
import { soulPrompt } from '../core/Soul';
import { rosterPrompt } from '../core/SubAgentRoster';
import { capsForModel, clampMaxTokens } from '../core/ModelCaps';
import { serviceTierFor } from '../core/FastMode';
import {
  ModelOverride,
  applyExtraBody,
  findModelOverride,
  mergeExtraHeaders
} from '../core/ModelOverride';
import { ApiMessage, ImageResolver, toApiMessages } from '../core/ToolProtocol';
import { ToolDefinition, ToolParameters } from '../core/ToolTypes';
import {
  SseParser,
  SseEvent,
  DeltaResult,
  ToolCallDelta,
  TokenUsage,
  parseOpenAiData,
  parseErrorMessage,
  OpenAiErrorDetail
} from '../core/SseParser';
import {
  chatCompletionsUrl,
  modelsUrl,
  normalizeBaseUrl,
  shouldAttachSessionHeader,
  OPENCODE_SESSION_HEADER
} from '../core/OpenCodeRules';
import {
  ANTHROPIC_VERSION,
  AnthropicRequestBody,
  AnthropicStreamState,
  anthropicMessagesUrl,
  anthropicModelsUrl,
  anthropicTools,
  buildAnthropicBody,
  buildAnthropicMessages,
  newAnthropicStreamState,
  parseAnthropicData
} from '../core/AnthropicProtocol';
import {
  GeminiRequestBody,
  GeminiStreamState,
  buildGeminiBody,
  buildGeminiContents,
  geminiGenerateUrl,
  geminiModelsUrl,
  geminiStreamUrl,
  geminiTools,
  newGeminiStreamState,
  parseGeminiData
} from '../core/GeminiProtocol';
import {
  CODEX_CLIENT_VERSION,
  CODEX_FALLBACK_MODELS,
  CODEX_USER_AGENT,
  ResponsesRequestBody,
  ResponsesStreamState,
  buildResponsesInput,
  buildResponsesTools,
  codexModelsUrl,
  newResponsesStreamState,
  parseResponsesData,
  promptCacheKey,
  responsesUrl
} from '../core/ResponsesProtocol';
import { t } from '../core/I18n';

const USER_AGENT: string = 'MinisHarmony/1.0 (HarmonyOS tablet)';
function summaryInstruction(): string {
  return t('你是对话压缩器。把给出的对话压缩成简洁的中文摘要，保留：') +
    t('用户目标与约束、已确认的事实与决定、改过的文件与命令、未完成事项。') +
    t('不要编造，不要加开场白，直接输出摘要正文。');
}

/**
 * Title request for the sidebar. Deliberately tiny (one short line), so the
 * answer can be used verbatim after `cleanTitle()` strips quotes/punctuation.
 */
function titleInstruction(folders: string[]): string {
  if (folders.length === 0) {
    return t('根据给出的对话起一个会话标题。') +
      t('要求：不超过20个字，只输出标题本身，不要引号、句号、前缀或解释；') +
      t('优先概括用户想完成的事情，用用户使用的语言。');
  }
  let list: string = '';
  for (let i = 0; i < folders.length; i++) {
    list += (i > 0 ? '、' : '') + folders[i];
  }
  return t('根据给出的对话起一个会话标题，并判断它属于哪个已有分组。') +
    t('要求：标题不超过20个字，概括用户想完成的事情，用用户使用的语言；') +
    t('分组只能从给出的名称中选择，不确定就填空字符串，不要发明新分组；') +
    t('只输出 JSON：{"title":"…","folder":""}，不要解释。') +
    t('已有分组：') + list;
}

export interface ChatCallbacks {
  onDelta: (content: string, reasoning: string, toolCalls: ToolCallDelta[]) => void;
  onUsage: (usage: TokenUsage) => void;
  onDone: (finishReason: string) => void;
  onError: (message: string) => void;
}

interface ApiToolFunctionDefinition {
  name: string;
  description: string;
  parameters: Object;
}

interface ApiToolDefinition {
  type: string;
  function: ApiToolFunctionDefinition;
}

interface StreamOptions {
  include_usage: boolean;
}

interface ChatRequestBody {
  model: string;
  messages: ApiMessage[];
  stream: boolean;
  stream_options?: StreamOptions;
  temperature?: number;
  top_p?: number;
  max_tokens?: number;
  /** Only sent when the user opted into thinking via /thinking. */
  reasoning_effort?: string;
  tools?: ApiToolDefinition[];
  tool_choice?: string;
  /** Only set for providers that document priority processing. */
  service_tier?: string;
}

interface ModelEntry {
  id?: string;
}

interface ModelsEnvelope {
  data?: ModelEntry[];
  error?: OpenAiErrorDetail;
}

interface GeminiModelEntry {
  name?: string;
  supportedGenerationMethods?: string[];
}

interface GeminiModelsEnvelope {
  models?: GeminiModelEntry[];
  error?: OpenAiErrorDetail;
}

export interface ModelsResult {
  ok: boolean;
  models: string[];
  message: string;
}

interface SummaryMessage {
  role: string;
  content: string;
}

interface SummaryRequestBody {
  model: string;
  messages: SummaryMessage[];
  stream: boolean;
  temperature: number;
  max_tokens: number;
  service_tier?: string;
}

interface SummaryChoiceMessage {
  content?: string;
}

interface SummaryChoice {
  message?: SummaryChoiceMessage;
}

interface SummaryEnvelope {
  choices?: SummaryChoice[];
  error?: OpenAiErrorDetail;
}

interface ResponsesSummaryRequestItem {
  role: string;
  content: string;
}

interface ResponsesSummaryRequest {
  model: string;
  instructions: string;
  input: ResponsesSummaryRequestItem[];
  stream: boolean;
  store: boolean;
  service_tier?: string;
}

interface ResponsesSummaryContent {
  type?: string;
  text?: string;
}

interface ResponsesSummaryItem {
  type?: string;
  content?: ResponsesSummaryContent[];
}

interface ResponsesSummaryEnvelope {
  output_text?: string;
  output?: ResponsesSummaryItem[];
  error?: OpenAiErrorDetail;
}

interface CodexModelEntry {
  slug?: string;
  id?: string;
  visibility?: string;
}

interface CodexModelsEnvelope {
  models?: CodexModelEntry[];
  data?: CodexModelEntry[];
  error?: OpenAiErrorDetail;
}

export interface SummaryResult {
  ok: boolean;
  text: string;
  message: string;
}

interface AnthropicSummaryBlock {
  type?: string;
  text?: string;
}

interface AnthropicSummaryEnvelope {
  content?: AnthropicSummaryBlock[];
  error?: OpenAiErrorDetail;
}

interface AnthropicSummaryRequestBody {
  model: string;
  max_tokens: number;
  temperature: number;
  system: string;
  messages: SummaryMessage[];
}

interface GeminiSummaryPart {
  text?: string;
}

interface GeminiSummaryContent {
  parts?: GeminiSummaryPart[];
}

interface GeminiSummaryCandidate {
  content?: GeminiSummaryContent;
}

interface GeminiSummaryEnvelope {
  candidates?: GeminiSummaryCandidate[];
  error?: OpenAiErrorDetail;
}

/**
 * Handle for an in-flight stream. Cancelling destroys the HTTP request and
 * suppresses every subsequent callback; the partial answer already delivered
 * through onDelta stays in the UI.
 */
export class ChatStreamHandle {
  private request: http.HttpRequest | null = null;
  private cancelled: boolean = false;

  attach(request: http.HttpRequest): void {
    this.request = request;
  }

  isCancelled(): boolean {
    return this.cancelled;
  }

  cancel(): void {
    this.cancelled = true;
    if (this.request !== null) {
      const current: http.HttpRequest = this.request;
      this.request = null;
      current.destroy();
    }
  }

  clear(): void {
    this.request = null;
  }
}

function describeNetworkError(error: BusinessError): string {
  return t('网络请求失败（') + error.code + t('）：') + error.message;
}

function httpErrorText(code: number, body: string): string {
  const detail: string = parseErrorMessage(body);
  let prefix: string = t('请求失败（HTTP ') + code + t('）');
  if (code === 400) {
    prefix = t('请求参数被拒绝（HTTP 400）');
  } else if (code === 401) {
    prefix = t('API Key 无效或未被授权（HTTP 401）');
  } else if (code === 402) {
    prefix = t('OpenCode Go 订阅额度不足（HTTP 402）');
  } else if (code === 403) {
    prefix = t('当前账号或区域无权访问该模型（HTTP 403）');
  } else if (code === 404) {
    prefix = t('接口地址或模型不存在（HTTP 404）');
  } else if (code === 429) {
    prefix = t('请求过于频繁，请稍后重试（HTTP 429）');
  } else if (code >= 500) {
    prefix = t('服务端暂时不可用（HTTP ') + code + t('）');
  }
  return detail.length > 0 ? prefix + t('：') + detail : prefix;
}

/** Soul persona + user prompt + recalled memory, in that order. */
function buildSystemPrompt(settings: AppSettings, memoryContext: string): string {
  let systemPrompt: string = settings.systemPrompt.trim();
  const soul: string = soulPrompt(settings.soulId).trim();
  if (soul.length > 0) {
    systemPrompt = systemPrompt.length > 0
      ? soul + '\n\n' + systemPrompt
      : soul;
  }
  const roster: string = rosterPrompt(settings.subAgents).trim();
  if (roster.length > 0) {
    systemPrompt = systemPrompt.length > 0
      ? systemPrompt + '\n\n' + roster
      : roster;
  }
  const memory: string = memoryContext.trim();
  if (memory.length > 0) {
    systemPrompt = systemPrompt.length > 0
      ? systemPrompt + '\n\n' + memory
      : memory;
  }
  return systemPrompt;
}

function buildMessages(
  settings: AppSettings,
  history: ChatMessage[],
  memoryContext: string,
  resolveImage: ImageResolver | null
): ApiMessage[] {
  const messages: ApiMessage[] = toApiMessages(history, resolveImage);
  const systemPrompt: string = buildSystemPrompt(settings, memoryContext);
  if (systemPrompt.length > 0) {
    messages.unshift({ role: 'system', content: systemPrompt });
  }
  return messages;
}

function buildToolDefinitions(tools: ToolDefinition[]): ApiToolDefinition[] {
  const definitions: ApiToolDefinition[] = [];
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
    definitions.push({
      type: 'function',
      function: {
        name: tools[i].name,
        description: tools[i].description,
        parameters: parameters
      }
    });
  }
  return definitions;
}

/**
 * Shared SSE transport. Both OpenAI-compatible and Anthropic streams differ
 * only in URL, headers, request body and the event decoder, so cancellation,
 * timeouts, error-body capture and finish handling live here once.
 */
function runStream(
  url: string,
  headers: Record<string, string>,
  payload: string,
  handle: ChatStreamHandle,
  callbacks: ChatCallbacks,
  decode: (data: string) => DeltaResult
): void {
  const options: http.HttpRequestOptions = {
    method: http.RequestMethod.POST,
    header: headers,
    extraData: payload,
    connectTimeout: 20000,
    readTimeout: 600000,
    usingCache: false
  };

  const request: http.HttpRequest = http.createHttp();
  handle.attach(request);

  const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  const parser: SseParser = new SseParser();
  let finished: boolean = false;
  let finishReason: string = '';
  let streamError: string = '';
  let tail: string = '';

  const cleanup = (): void => {
    try {
      request.off('dataReceive');
      request.off('dataEnd');
    } catch (e) {
      // The request may already be destroyed.
    }
    try {
      request.destroy();
    } catch (e) {
      // Ignore double destroy.
    }
    handle.clear();
  };

  const fail = (message: string): void => {
    if (finished || handle.isCancelled()) {
      return;
    }
    finished = true;
    cleanup();
    callbacks.onError(message);
  };

  const succeed = (): void => {
    if (finished || handle.isCancelled()) {
      return;
    }
    finished = true;
    cleanup();
    callbacks.onDone(finishReason);
  };

  const consumeEvent = (event: SseEvent): void => {
    const delta: DeltaResult = decode(event.data);
    // Providers may put JSON null in string fields. Types say otherwise, but
    // this runs on data that came off the wire, so coerce before use.
    const errorText: string = typeof delta.error === 'string' ? delta.error : '';
    const content: string = typeof delta.content === 'string' ? delta.content : '';
    const reasoning: string = typeof delta.reasoning === 'string' ? delta.reasoning : '';
    const finish: string = typeof delta.finishReason === 'string' ? delta.finishReason : '';
    const calls: ToolCallDelta[] = delta.toolCalls !== undefined && delta.toolCalls !== null
      ? delta.toolCalls
      : [];
    if (errorText.length > 0) {
      streamError = errorText;
      return;
    }
    if (content.length > 0 || reasoning.length > 0 || calls.length > 0) {
      callbacks.onDelta(content, reasoning, calls);
    }
    if (delta.usage !== undefined && delta.usage !== null && delta.usage.present) {
      callbacks.onUsage(delta.usage);
    }
    if (finish.length > 0) {
      finishReason = finish;
    }
    if (delta.done && streamError.length === 0) {
      // Some servers stop after [DONE]; finalisation still waits for the
      // request callback so an HTTP error status can win.
      finishReason = finishReason.length > 0 ? finishReason : 'stop';
    }
  };

  const consumeText = (text: string): void => {
    if (text.length === 0) {
      return;
    }
    if (tail.length < 8192) {
      tail += text;
    } else {
      tail = tail.substring(tail.length - 4096) + text;
    }
    const events: SseEvent[] = parser.push(text);
    for (let i = 0; i < events.length; i++) {
      consumeEvent(events[i]);
      if (streamError.length > 0) {
        break;
      }
    }
    if (streamError.length > 0) {
      fail(streamError);
    }
  };

  request.on('dataReceive', (data: ArrayBuffer) => {
    if (finished || handle.isCancelled()) {
      return;
    }
    let text: string = '';
    try {
      text = decoder.decodeToString(new Uint8Array(data), { stream: true });
    } catch (e) {
      text = decoder.decodeToString(new Uint8Array(data));
    }
    consumeText(text);
  });

  request.on('dataEnd', () => {
    if (finished || handle.isCancelled()) {
      return;
    }
    let rest: string = '';
    try {
      rest = decoder.decodeToString(new Uint8Array(0), { stream: false });
    } catch (e) {
      rest = '';
    }
    consumeText(rest);
    const pending: SseEvent[] = parser.flush();
    for (let i = 0; i < pending.length; i++) {
      consumeEvent(pending[i]);
    }
  });

  try {
    request.requestInStream(url, options, (err: BusinessError, code: number) => {
      if (finished || handle.isCancelled()) {
        return;
      }
      if (err) {
        fail(describeNetworkError(err));
        return;
      }
      if (code >= 400) {
        fail(httpErrorText(code, tail));
        return;
      }
      if (streamError.length > 0) {
        fail(streamError);
        return;
      }
      succeed();
    });
  } catch (e) {
    const error: BusinessError = e as BusinessError;
    fail(t('无法发起请求：') + error.message);
  }
}

/**
 * Start a streaming chat completion.
 *
 * `sessionId` is the persisted conversation id. When the endpoint is
 * opencode.ai, it is sent as `x-opencode-session` on every request; for any
 * other host it is deliberately not sent.
 */
export function startChatStream(
  settings: AppSettings,
  sessionId: string,
  history: ChatMessage[],
  tools: ToolDefinition[],
  memoryContext: string,
  callbacks: ChatCallbacks,
  resolveImage: ImageResolver | null = null
): ChatStreamHandle {
  const handle: ChatStreamHandle = new ChatStreamHandle();
  const baseUrl: string = normalizeBaseUrl(settings.baseUrl);
  const apiKey: string = settings.apiKey.trim();

  if (baseUrl.length === 0) {
    callbacks.onError(t('请先在设置中填写 API 地址'));
    return handle;
  }
  if (apiKey.length === 0 && bearerToken(settings).length === 0) {
    callbacks.onError(t('请先在设置中填写 API Key，或登录服务商账号'));
    return handle;
  }
  if (settings.preset === 'anthropic') {
    startAnthropicStream(
      settings, history, tools, memoryContext, callbacks, resolveImage, handle);
    return handle;
  }
  if (settings.preset === 'gemini') {
    startGeminiStream(
      settings, history, tools, memoryContext, callbacks, resolveImage, handle);
    return handle;
  }
  if (settings.preset === 'codex') {
    startResponsesStream(
      settings, history, tools, memoryContext, callbacks, resolveImage, handle);
    return handle;
  }

  const caps = capsForModel(settings.modelId);
  const body: ChatRequestBody = {
    model: settings.modelId,
    messages: buildMessages(settings, history, memoryContext, resolveImage),
    stream: true,
    stream_options: { include_usage: true },
    temperature: settings.temperature,
    max_tokens: clampMaxTokens(settings.maxTokens, caps)
  };
  if (settings.thinkingLevel !== 'off') {
    body.reasoning_effort = settings.thinkingLevel;
  }
  if (tools.length > 0) {
    body.tools = buildToolDefinitions(tools);
    body.tool_choice = 'auto';
  }
  const overrides: ModelOverride[] = settings.modelOverrides !== undefined ? settings.modelOverrides : [];
  const override: ModelOverride | null = findModelOverride(overrides, settings.modelId);
  if (override !== null) {
    if (override.temperature >= 0) {
      body.temperature = override.temperature;
    }
    if (override.topP >= 0) {
      body.top_p = override.topP;
    }
    if (override.maxTokens > 0) {
      body.max_tokens = clampMaxTokens(override.maxTokens, caps);
    }
  }
  const tier: string = serviceTierFor(
    settings.fastMode, settings.preset, settings.baseUrl);
  if (tier.length > 0) {
    body.service_tier = tier;
  }

  let headers: Record<string, string> = settings.preset === 'copilot'
    ? copilotHeaders(settings, 'text/event-stream', history)
    : {
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      'Authorization': 'Bearer ' + apiKey,
      'User-Agent': USER_AGENT
    };
  if (settings.preset !== 'copilot' && shouldAttachSessionHeader(baseUrl, sessionId)) {
    headers[OPENCODE_SESSION_HEADER] = sessionId;
  }
  if (override !== null) {
    headers = mergeExtraHeaders(headers, override.extraHeaders);
  }
  const payload: string = override !== null
    ? applyExtraBody(JSON.stringify(body), override.extraBody)
    : JSON.stringify(body);

  runStream(chatCompletionsUrl(baseUrl), headers, payload, handle, callbacks,
    (data: string): DeltaResult => parseOpenAiData(data));
  return handle;
}

/**
 * Anthropic Messages API path. The request shape differs enough (top-level
 * system, tool_use/tool_result blocks, x-api-key) that only the SSE transport
 * is shared with the OpenAI path.
 *
 * `thinkingLevel` is intentionally not mapped: extended thinking needs a
 * token budget and forbids temperature, which the generic setting does not
 * express. Users can add it through a per-model extra body instead.
 */
function bearerToken(settings: AppSettings): string {
  const oauth: string = settings.oauthToken !== undefined ? settings.oauthToken.trim() : '';
  return oauth.length > 0 ? oauth : settings.apiKey.trim();
}

/**
 * GitHub Copilot's undocumented API wants a plausible editor identity and an
 * `X-Initiator` that says who drove the turn. Mislabelling agent traffic as a
 * human is the direction that gets accounts flagged, so it is derived from the
 * transcript rather than hard-coded.
 */
function copilotHeaders(
  settings: AppSettings,
  accept: string,
  history: ChatMessage[]
): Record<string, string> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'Accept': accept,
    'Authorization': 'Bearer ' + bearerToken(settings),
    'Editor-Version': 'vscode/1.104.0',
    'Editor-Plugin-Version': 'copilot-chat/0.31.0',
    'User-Agent': 'GitHubCopilotChat/0.31.0',
    'Copilot-Integration-Id': 'vscode-chat',
    'X-GitHub-Api-Version': '2025-04-01',
    'Openai-Intent': 'conversation-panel',
    'X-Request-Id': util.generateRandomUUID(true)
  };
  let agentTurn: boolean = false;
  let hasImages: boolean = false;
  if (history.length > 0) {
    agentTurn = history[history.length - 1].role === 'tool';
    for (let i = 0; i < history.length; i++) {
      const parts = history[i].parts;
      for (let j = 0; j < parts.length; j++) {
        if (parts[j].kind === PART_IMAGE) {
          hasImages = true;
        }
      }
    }
  }
  headers['X-Initiator'] = agentTurn ? 'agent' : 'user';
  if (hasImages) {
    headers['Copilot-Vision-Request'] = 'true';
  }
  return headers;
}

/** `x-api-key` for API keys, `Bearer` + CLI profile for an OAuth login. */
function anthropicAuthHeaders(settings: AppSettings, accept: string): Record<string, string> {
  const token: string = settings.oauthToken !== undefined ? settings.oauthToken.trim() : '';
  if (token.length > 0) {
    const headers: Record<string, string> = claudeOAuthRequestHeaders();
    headers['Content-Type'] = 'application/json';
    headers['Accept'] = accept;
    headers['anthropic-version'] = ANTHROPIC_VERSION;
    headers['Authorization'] = 'Bearer ' + token;
    return headers;
  }
  return {
    'Content-Type': 'application/json',
    'Accept': accept,
    'x-api-key': settings.apiKey.trim(),
    'anthropic-version': ANTHROPIC_VERSION,
    'User-Agent': USER_AGENT
  };
}

/**
 * ChatGPT Codex identity. The backend gates account access on this exact
 * client fingerprint (`codex_cli_rs`), so these headers are not arbitrary:
 * a different name or version is refused even with a valid token.
 */
function codexHeaders(settings: AppSettings, accept: string): Record<string, string> {
  const token: string = settings.oauthToken !== undefined ? settings.oauthToken.trim() : '';
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'Accept': accept,
    'Authorization': 'Bearer ' + token,
    'Version': CODEX_CLIENT_VERSION,
    'Openai-Beta': 'responses=experimental',
    'User-Agent': CODEX_USER_AGENT,
    'Originator': 'codex_cli_rs'
  };
  const account: string = settings.oauthAccountId !== undefined
    ? settings.oauthAccountId.trim() : '';
  if (account.length > 0) {
    headers['Chatgpt-Account-Id'] = account;
  }
  return headers;
}

/**
 * The Responses API path used by a ChatGPT-account login. Same SSE transport
 * as the other protocols; only the body shape and event decoder differ.
 *
 * The Codex backend refuses a request without a `reasoning` object, so the
 * level is clamped to `low` when the user has thinking off rather than being
 * omitted. `summary: auto` is what makes human-readable reasoning stream back;
 * without it only encrypted content is returned.
 */
function startResponsesStream(
  settings: AppSettings,
  history: ChatMessage[],
  tools: ToolDefinition[],
  memoryContext: string,
  callbacks: ChatCallbacks,
  resolveImage: ImageResolver | null,
  handle: ChatStreamHandle
): void {
  const baseUrl: string = normalizeBaseUrl(settings.baseUrl);
  if (baseUrl.length === 0) {
    callbacks.onError(t('请先在设置中填写 API 地址'));
    return;
  }
  const token: string = settings.oauthToken !== undefined ? settings.oauthToken.trim() : '';
  if (token.length === 0) {
    callbacks.onError(t('请先登录 ChatGPT 账号'));
    return;
  }
  const messages: ApiMessage[] = toApiMessages(history, resolveImage);
  const instructions: string = buildSystemPrompt(settings, memoryContext);
  const body: ResponsesRequestBody = {
    model: settings.modelId,
    input: buildResponsesInput(messages),
    stream: true,
    store: false,
    parallel_tool_calls: true,
    include: ['reasoning.encrypted_content'],
    reasoning: {
      effort: settings.thinkingLevel !== 'off' ? settings.thinkingLevel : 'low',
      summary: 'auto'
    }
  };
  if (instructions.length > 0) {
    body.instructions = instructions;
  }
  if (tools.length > 0) {
    body.tools = buildResponsesTools(tools);
    body.tool_choice = 'auto';
  }
  const cacheKey: string = promptCacheKey(messages);
  if (cacheKey.length > 0) {
    body.prompt_cache_key = cacheKey;
  }
  if (settings.fastMode) {
    body.service_tier = 'priority';
  }

  const overrides: ModelOverride[] = settings.modelOverrides !== undefined ? settings.modelOverrides : [];
  const override: ModelOverride | null = findModelOverride(overrides, settings.modelId);
  let headers: Record<string, string> = codexHeaders(settings, 'text/event-stream');
  if (override !== null) {
    headers = mergeExtraHeaders(headers, override.extraHeaders);
  }
  const payload: string = override !== null
    ? applyExtraBody(JSON.stringify(body), override.extraBody)
    : JSON.stringify(body);
  const state: ResponsesStreamState = newResponsesStreamState();
  runStream(responsesUrl(baseUrl), headers, payload, handle, callbacks,
    (data: string): DeltaResult => parseResponsesData(data, state));
}

function startAnthropicStream(
  settings: AppSettings,
  history: ChatMessage[],
  tools: ToolDefinition[],
  memoryContext: string,
  callbacks: ChatCallbacks,
  resolveImage: ImageResolver | null,
  handle: ChatStreamHandle
): void {
  const baseUrl: string = normalizeBaseUrl(settings.baseUrl);
  const apiKey: string = settings.apiKey.trim();
  const oauthToken: string = settings.oauthToken !== undefined
    ? settings.oauthToken.trim() : '';
  if (baseUrl.length === 0) {
    callbacks.onError(t('请先在设置中填写 API 地址'));
    return;
  }
  if (apiKey.length === 0 && oauthToken.length === 0) {
    callbacks.onError(t('请先在设置中填写 API Key，或登录 Claude 账号'));
    return;
  }
  const caps = capsForModel(settings.modelId);
  let temperature: number = settings.temperature;
  let topP: number = 0;
  let maxTokens: number = clampMaxTokens(settings.maxTokens, caps);
  const overrides: ModelOverride[] = settings.modelOverrides !== undefined ? settings.modelOverrides : [];
  const override: ModelOverride | null = findModelOverride(overrides, settings.modelId);
  if (override !== null) {
    if (override.temperature >= 0) {
      temperature = override.temperature;
    }
    if (override.topP >= 0) {
      topP = override.topP;
    }
    if (override.maxTokens > 0) {
      maxTokens = clampMaxTokens(override.maxTokens, caps);
    }
  }

  const parts = buildAnthropicMessages(history, resolveImage);
  const body: AnthropicRequestBody = buildAnthropicBody(
    settings.modelId,
    maxTokens,
    buildSystemPrompt(settings, memoryContext),
    parts.messages,
    anthropicTools(tools),
    temperature,
    topP
  );

  let headers: Record<string, string> =
    anthropicAuthHeaders(settings, 'text/event-stream');
  if (override !== null) {
    headers = mergeExtraHeaders(headers, override.extraHeaders);
  }
  const payload: string = override !== null
    ? applyExtraBody(JSON.stringify(body), override.extraBody)
    : JSON.stringify(body);

  const state: AnthropicStreamState = newAnthropicStreamState();
  runStream(anthropicMessagesUrl(baseUrl), headers, payload, handle, callbacks,
    (data: string): DeltaResult => parseAnthropicData(data, state));
}

/**
 * Gemini `streamGenerateContent` path. The model id is part of the URL, the
 * key travels in `x-goog-api-key`, and tool results are functionResponse
 * parts rather than dedicated messages.
 */
function startGeminiStream(
  settings: AppSettings,
  history: ChatMessage[],
  tools: ToolDefinition[],
  memoryContext: string,
  callbacks: ChatCallbacks,
  resolveImage: ImageResolver | null,
  handle: ChatStreamHandle
): void {
  const baseUrl: string = normalizeBaseUrl(settings.baseUrl);
  const apiKey: string = settings.apiKey.trim();
  if (baseUrl.length === 0) {
    callbacks.onError(t('请先在设置中填写 API 地址'));
    return;
  }
  if (apiKey.length === 0) {
    callbacks.onError(t('请先在设置中填写 API Key'));
    return;
  }
  const caps = capsForModel(settings.modelId);
  let temperature: number = settings.temperature;
  let topP: number = 0;
  let maxTokens: number = clampMaxTokens(settings.maxTokens, caps);
  const overrides: ModelOverride[] = settings.modelOverrides !== undefined ? settings.modelOverrides : [];
  const override: ModelOverride | null = findModelOverride(overrides, settings.modelId);
  if (override !== null) {
    if (override.temperature >= 0) {
      temperature = override.temperature;
    }
    if (override.topP >= 0) {
      topP = override.topP;
    }
    if (override.maxTokens > 0) {
      maxTokens = clampMaxTokens(override.maxTokens, caps);
    }
  }

  const parts = buildGeminiContents(history, resolveImage);
  const body: GeminiRequestBody = buildGeminiBody(
    settings.modelId,
    maxTokens,
    buildSystemPrompt(settings, memoryContext),
    parts.contents,
    geminiTools(tools),
    temperature,
    topP
  );

  let headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'Accept': 'text/event-stream',
    'x-goog-api-key': apiKey,
    'User-Agent': USER_AGENT
  };
  if (override !== null) {
    headers = mergeExtraHeaders(headers, override.extraHeaders);
  }
  const payload: string = override !== null
    ? applyExtraBody(JSON.stringify(body), override.extraBody)
    : JSON.stringify(body);

  const state: GeminiStreamState = newGeminiStreamState();
  runStream(geminiStreamUrl(baseUrl, settings.modelId), headers, payload, handle, callbacks,
    (data: string): DeltaResult => parseGeminiData(data, state));
}

/** Non-streaming `/compact` request for Gemini. */
async function summarizeGemini(
  settings: AppSettings,
  transcript: string,
  instruction: string,
  maxOutputTokens: number
): Promise<SummaryResult> {
  const baseUrl: string = normalizeBaseUrl(settings.baseUrl);
  const body: GeminiRequestBody = {
    contents: [{ role: 'user', parts: [{ text: transcript }] }],
    systemInstruction: { parts: [{ text: instruction }] },
    generationConfig: { maxOutputTokens: maxOutputTokens, temperature: 0.2 }
  };
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'x-goog-api-key': settings.apiKey.trim(),
    'User-Agent': USER_AGENT
  };
  const options: http.HttpRequestOptions = {
    method: http.RequestMethod.POST,
    header: headers,
    extraData: JSON.stringify(body),
    connectTimeout: 20000,
    readTimeout: 180000,
    usingCache: false,
    expectDataType: http.HttpDataType.STRING
  };
  const request: http.HttpRequest = http.createHttp();
  try {
    const response: http.HttpResponse = await request.request(
      geminiGenerateUrl(baseUrl, settings.modelId), options
    );
    const raw: string = response.result as string;
    if (response.responseCode < 200 || response.responseCode >= 300) {
      return {
        ok: false,
        text: '',
        message: httpErrorText(response.responseCode, raw)
      };
    }
    const envelope: GeminiSummaryEnvelope = JSON.parse(raw) as GeminiSummaryEnvelope;
    let text: string = '';
    if (envelope.candidates !== undefined && envelope.candidates.length > 0) {
      const candidate: GeminiSummaryCandidate = envelope.candidates[0];
      if (candidate.content !== undefined && candidate.content.parts !== undefined) {
        for (let i = 0; i < candidate.content.parts.length; i++) {
          const part: GeminiSummaryPart = candidate.content.parts[i];
          if (part.text !== undefined) {
            text += part.text;
          }
        }
      }
    }
    text = text.trim();
    if (text.length === 0) {
      return { ok: false, text: '', message: t('模型没有返回摘要') };
    }
    return { ok: true, text: text, message: t('已生成摘要') };
  } catch (e) {
    const error: BusinessError = e as BusinessError;
    return { ok: false, text: '', message: describeNetworkError(error) };
  } finally {
    request.destroy();
  }
}

/** Non-streaming `/compact` request for the Messages API. */
async function summarizeAnthropic(
  settings: AppSettings,
  transcript: string,
  instruction: string,
  maxTokens: number
): Promise<SummaryResult> {
  const baseUrl: string = normalizeBaseUrl(settings.baseUrl);
  const body: AnthropicSummaryRequestBody = {
    model: settings.modelId,
    max_tokens: maxTokens,
    temperature: 0.2,
    system: instruction,
    messages: [{ role: 'user', content: transcript }]
  };
  const headers: Record<string, string> =
    anthropicAuthHeaders(settings, 'application/json');
  const options: http.HttpRequestOptions = {
    method: http.RequestMethod.POST,
    header: headers,
    extraData: JSON.stringify(body),
    connectTimeout: 20000,
    readTimeout: 180000,
    usingCache: false,
    expectDataType: http.HttpDataType.STRING
  };
  const request: http.HttpRequest = http.createHttp();
  try {
    const response: http.HttpResponse = await request.request(
      anthropicMessagesUrl(baseUrl), options
    );
    const raw: string = response.result as string;
    if (response.responseCode < 200 || response.responseCode >= 300) {
      return {
        ok: false,
        text: '',
        message: httpErrorText(response.responseCode, raw)
      };
    }
    const envelope: AnthropicSummaryEnvelope = JSON.parse(raw) as AnthropicSummaryEnvelope;
    let text: string = '';
    if (envelope.content !== undefined) {
      for (let i = 0; i < envelope.content.length; i++) {
        const block: AnthropicSummaryBlock = envelope.content[i];
        if (block.type === 'text' && block.text !== undefined) {
          text += block.text;
        }
      }
    }
    text = text.trim();
    if (text.length === 0) {
      return { ok: false, text: '', message: t('模型没有返回摘要') };
    }
    return { ok: true, text: text, message: t('已生成摘要') };
  } catch (e) {
    const error: BusinessError = e as BusinessError;
    return { ok: false, text: '', message: describeNetworkError(error) };
  } finally {
    request.destroy();
  }
}

/** Non-streaming `/compact` request for the Responses API. */
async function summarizeResponses(
  settings: AppSettings,
  transcript: string,
  instruction: string
): Promise<SummaryResult> {
  const baseUrl: string = normalizeBaseUrl(settings.baseUrl);
  const body: ResponsesSummaryRequest = {
    model: settings.modelId,
    instructions: instruction,
    input: [{ role: 'user', content: transcript }],
    stream: false,
    store: false
  };
  if (settings.fastMode) {
    body.service_tier = 'priority';
  }
  const headers: Record<string, string> = codexHeaders(settings, 'application/json');
  const options: http.HttpRequestOptions = {
    method: http.RequestMethod.POST,
    header: headers,
    extraData: JSON.stringify(body),
    connectTimeout: 20000,
    readTimeout: 180000,
    usingCache: false,
    expectDataType: http.HttpDataType.STRING
  };
  const request: http.HttpRequest = http.createHttp();
  try {
    const response: http.HttpResponse = await request.request(responsesUrl(baseUrl), options);
    const raw: string = response.result as string;
    if (response.responseCode < 200 || response.responseCode >= 300) {
      return {
        ok: false,
        text: '',
        message: httpErrorText(response.responseCode, raw)
      };
    }
    const envelope: ResponsesSummaryEnvelope = JSON.parse(raw) as ResponsesSummaryEnvelope;
    let text: string = typeof envelope.output_text === 'string' ? envelope.output_text : '';
    if (text.length === 0 && envelope.output !== undefined) {
      for (let i = 0; i < envelope.output.length; i++) {
        const item: ResponsesSummaryItem = envelope.output[i];
        if (item.content === undefined) {
          continue;
        }
        for (let j = 0; j < item.content.length; j++) {
          const block: ResponsesSummaryContent = item.content[j];
          if (block.type === 'output_text' && block.text !== undefined) {
            text += block.text;
          }
        }
      }
    }
    text = text.trim();
    if (text.length === 0) {
      return { ok: false, text: '', message: t('模型没有返回摘要') };
    }
    return { ok: true, text: text, message: t('已生成摘要') };
  } catch (e) {
    const error: BusinessError = e as BusinessError;
    return { ok: false, text: '', message: describeNetworkError(error) };
  } finally {
    request.destroy();
  }
}

/**
 * Ask the model to summarise an old transcript for `/compact`.
 *
 * This is a non-streaming request: the caller blocks until the summary is
 * complete, then replaces the old turns with one system message. It reuses the
 * same session id (so OpenCode routing/cache stays stable) but sends no tools.
 */
export async function summarizeConversation(
  settings: AppSettings,
  sessionId: string,
  transcript: string
): Promise<SummaryResult> {
  const problem: string = modelTextProblem(settings, transcript, t('没有可压缩的内容'));
  if (problem.length > 0) {
    return { ok: false, text: '', message: problem };
  }
  return await requestModelText(
    settings, sessionId, transcript, summaryInstruction(), 1500);
}

/**
 * Ask the model for a short sidebar title after the first settled turn.
 *
 * Reuses the summary transport (protocol-specific non-streaming request) but
 * with a different instruction and a tiny output budget.
 */
export async function generateSessionTitle(
  settings: AppSettings,
  sessionId: string,
  transcript: string,
  folders: string[] = []
): Promise<SummaryResult> {
  const problem: string = modelTextProblem(settings, transcript, t('没有可命名的内容'));
  if (problem.length > 0) {
    return { ok: false, text: '', message: problem };
  }
  return await requestModelText(
    settings, sessionId, transcript, titleInstruction(folders), 200);
}

/** Empty string when the request is usable; otherwise a user-facing reason. */
function modelTextProblem(
  settings: AppSettings,
  transcript: string,
  emptyReason: string
): string {
  const baseUrl: string = normalizeBaseUrl(settings.baseUrl);
  if (baseUrl.length === 0) {
    return t('请先在设置中填写 API 地址');
  }
  if (settings.apiKey.trim().length === 0 && bearerToken(settings).length === 0) {
    return t('请先在设置中填写 API Key，或登录服务商账号');
  }
  if (transcript.trim().length === 0) {
    return emptyReason;
  }
  return '';
}

/** One non-streaming request routed by the configured protocol. */
export async function requestModelText(
  settings: AppSettings,
  sessionId: string,
  transcript: string,
  instruction: string,
  maxTokens: number
): Promise<SummaryResult> {
  if (settings.preset === 'anthropic') {
    return await summarizeAnthropic(settings, transcript, instruction, maxTokens);
  }
  if (settings.preset === 'gemini') {
    return await summarizeGemini(settings, transcript, instruction, maxTokens);
  }
  if (settings.preset === 'codex') {
    return await summarizeResponses(settings, transcript, instruction);
  }

  const baseUrl: string = normalizeBaseUrl(settings.baseUrl);
  const apiKey: string = settings.apiKey.trim();
  const body: SummaryRequestBody = {
    model: settings.modelId,
    messages: [
      {
        role: 'system',
        content: instruction
      },
      {
        role: 'user',
        content: transcript
      }
    ],
    stream: false,
    temperature: 0.2,
    max_tokens: maxTokens
  };
  const summaryTier: string =
    serviceTierFor(settings.fastMode, settings.preset, settings.baseUrl);
  if (summaryTier.length > 0) {
    body.service_tier = summaryTier;
  }

  const headers: Record<string, string> = settings.preset === 'copilot'
    ? copilotHeaders(settings, 'application/json', [])
    : {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer ' + apiKey,
      'User-Agent': USER_AGENT
    };
  if (settings.preset !== 'copilot' && shouldAttachSessionHeader(baseUrl, sessionId)) {
    headers[OPENCODE_SESSION_HEADER] = sessionId;
  }
  const options: http.HttpRequestOptions = {
    method: http.RequestMethod.POST,
    header: headers,
    extraData: JSON.stringify(body),
    connectTimeout: 20000,
    readTimeout: 180000,
    usingCache: false,
    expectDataType: http.HttpDataType.STRING
  };

  const request: http.HttpRequest = http.createHttp();
  try {
    const response: http.HttpResponse = await request.request(
      chatCompletionsUrl(baseUrl), options
    );
    const raw: string = response.result as string;
    if (response.responseCode < 200 || response.responseCode >= 300) {
      return {
        ok: false,
        text: '',
        message: httpErrorText(response.responseCode, raw)
      };
    }
    const envelope: SummaryEnvelope = JSON.parse(raw) as SummaryEnvelope;
    if (envelope.choices === undefined || envelope.choices.length === 0) {
      return { ok: false, text: '', message: t('模型没有返回摘要') };
    }
    const choice: SummaryChoice = envelope.choices[0];
    if (choice.message === undefined || choice.message.content === undefined) {
      return { ok: false, text: '', message: t('模型没有返回摘要') };
    }
    const text: string = choice.message.content.trim();
    if (text.length === 0) {
      return { ok: false, text: '', message: t('模型返回了空摘要') };
    }
    return { ok: true, text: text, message: t('已生成摘要') };
  } catch (e) {
    const error: BusinessError = e as BusinessError;
    return { ok: false, text: '', message: describeNetworkError(error) };
  } finally {
    request.destroy();
  }
}

/**
 * Fetch model ids for the configured endpoint. For OpenCode this hits the
 * gateway's models path (`/zen/go/v1/models` for the canonical base) rather
 * than the inference path.
 */
async function fetchGeminiModelIds(settings: AppSettings): Promise<ModelsResult> {
  const headers: Record<string, string> = {
    'Accept': 'application/json',
    'x-goog-api-key': settings.apiKey.trim(),
    'User-Agent': USER_AGENT
  };
  const options: http.HttpRequestOptions = {
    method: http.RequestMethod.GET,
    header: headers,
    connectTimeout: 15000,
    readTimeout: 30000,
    usingCache: false,
    expectDataType: http.HttpDataType.STRING
  };
  const request: http.HttpRequest = http.createHttp();
  try {
    const response: http.HttpResponse = await request.request(
      geminiModelsUrl(settings.baseUrl) + '?pageSize=1000', options);
    const raw: string = response.result as string;
    if (response.responseCode < 200 || response.responseCode >= 300) {
      return {
        ok: false,
        models: [],
        message: httpErrorText(response.responseCode, raw)
      };
    }
    const envelope: GeminiModelsEnvelope = JSON.parse(raw) as GeminiModelsEnvelope;
    const list: string[] = [];
    if (envelope.models !== undefined) {
      for (let i = 0; i < envelope.models.length; i++) {
        const entry: GeminiModelEntry = envelope.models[i];
        if (entry.name === undefined || entry.name.length === 0) {
          continue;
        }
        if (entry.supportedGenerationMethods !== undefined &&
          entry.supportedGenerationMethods.indexOf('generateContent') < 0) {
          continue;
        }
        const id: string = entry.name.indexOf('models/') === 0
          ? entry.name.substring('models/'.length) : entry.name;
        if (id.length > 0 && list.indexOf(id) < 0) {
          list.push(id);
        }
      }
    }
    list.sort();
    if (list.length === 0) {
      return { ok: true, models: [], message: t('连接成功，但服务没有返回模型列表') };
    }
    return { ok: true, models: list, message: t('连接成功，发现 ') + list.length + t(' 个模型') };
  } catch (e) {
    const error: BusinessError = e as BusinessError;
    return { ok: false, models: [], message: describeNetworkError(error) };
  } finally {
    request.destroy();
  }
}

async function fetchAnthropicModelIds(settings: AppSettings): Promise<ModelsResult> {
  const headers: Record<string, string> =
    anthropicAuthHeaders(settings, 'application/json');
  const options: http.HttpRequestOptions = {
    method: http.RequestMethod.GET,
    header: headers,
    connectTimeout: 15000,
    readTimeout: 30000,
    usingCache: false,
    expectDataType: http.HttpDataType.STRING
  };
  const request: http.HttpRequest = http.createHttp();
  try {
    const response: http.HttpResponse = await request.request(
      anthropicModelsUrl(settings.baseUrl) + '?limit=1000', options);
    const raw: string = response.result as string;
    if (response.responseCode < 200 || response.responseCode >= 300) {
      return {
        ok: false,
        models: [],
        message: httpErrorText(response.responseCode, raw)
      };
    }
    const envelope: ModelsEnvelope = JSON.parse(raw) as ModelsEnvelope;
    const list: string[] = [];
    if (envelope.data !== undefined) {
      for (let i = 0; i < envelope.data.length; i++) {
        const entry: ModelEntry = envelope.data[i];
        if (entry.id !== undefined && entry.id.length > 0 && list.indexOf(entry.id) < 0) {
          list.push(entry.id);
        }
      }
    }
    list.sort();
    if (list.length === 0) {
      return { ok: true, models: [], message: t('连接成功，但服务没有返回模型列表') };
    }
    return { ok: true, models: list, message: t('连接成功，发现 ') + list.length + t(' 个模型') };
  } catch (e) {
    const error: BusinessError = e as BusinessError;
    return { ok: false, models: [], message: describeNetworkError(error) };
  } finally {
    request.destroy();
  }
}

function codexFallback(message: string): ModelsResult {
  return { ok: true, models: CODEX_FALLBACK_MODELS.slice(), message: message };
}

/**
 * The Codex backend has its own discovery route; the regular `/v1/models`
 * path rejects an OAuth token. A network or parse failure falls back to the
 * known-good list instead of leaving the picker empty, while a rejected
 * credential is reported as such so the user signs in again.
 */
async function fetchCodexModelIds(settings: AppSettings): Promise<ModelsResult> {
  const baseUrl: string = normalizeBaseUrl(settings.baseUrl);
  const token: string = settings.oauthToken !== undefined ? settings.oauthToken.trim() : '';
  if (token.length === 0) {
    return { ok: false, models: [], message: t('请先登录 ChatGPT 账号') };
  }
  const headers: Record<string, string> = codexHeaders(settings, 'application/json');
  const options: http.HttpRequestOptions = {
    method: http.RequestMethod.GET,
    header: headers,
    connectTimeout: 15000,
    readTimeout: 30000,
    usingCache: false,
    expectDataType: http.HttpDataType.STRING
  };
  const url: string = codexModelsUrl(baseUrl) + '?client_version=' + CODEX_CLIENT_VERSION;
  const request: http.HttpRequest = http.createHttp();
  try {
    const response: http.HttpResponse = await request.request(url, options);
    const raw: string = response.result as string;
    if (response.responseCode === 401 || response.responseCode === 403) {
      return { ok: false, models: [], message: t('ChatGPT 登录已失效，请重新登录') };
    }
    if (response.responseCode < 200 || response.responseCode >= 300) {
      return codexFallback(t('连接失败（HTTP ') + response.responseCode.toString() + t('），已使用内置模型列表'));
    }
    const envelope: CodexModelsEnvelope = JSON.parse(raw) as CodexModelsEnvelope;
    const entries: CodexModelEntry[] | undefined =
      envelope.models !== undefined ? envelope.models : envelope.data;
    const list: string[] = [];
    if (entries !== undefined) {
      for (let i = 0; i < entries.length; i++) {
        const entry: CodexModelEntry = entries[i];
        const visibility: string = entry.visibility !== undefined
          ? entry.visibility.trim().toLowerCase() : '';
        if (visibility === 'hide' || visibility === 'hidden') {
          continue;
        }
        const id: string = entry.slug !== undefined && entry.slug.length > 0
          ? entry.slug : (entry.id !== undefined ? entry.id : '');
        if (id.length > 0 && list.indexOf(id) < 0) {
          list.push(id);
        }
      }
    }
    if (list.length === 0) {
      return codexFallback(t('账号没有返回可用模型，已使用内置模型列表'));
    }
    return { ok: true, models: list, message: t('连接成功，发现 ') + list.length + t(' 个模型') };
  } catch (e) {
    const error: BusinessError = e as BusinessError;
    return codexFallback(describeNetworkError(error) + t('，已使用内置模型列表'));
  } finally {
    request.destroy();
  }
}

export async function fetchModelIds(settings: AppSettings): Promise<ModelsResult> {
  const baseUrl: string = normalizeBaseUrl(settings.baseUrl);
  if (baseUrl.length === 0) {
    return { ok: false, models: [], message: t('请先填写 API 地址') };
  }
  if (settings.preset === 'anthropic') {
    return await fetchAnthropicModelIds(settings);
  }
  if (settings.preset === 'gemini') {
    return await fetchGeminiModelIds(settings);
  }
  if (settings.preset === 'codex') {
    return await fetchCodexModelIds(settings);
  }
  const headers: Record<string, string> = settings.preset === 'copilot'
    ? copilotHeaders(settings, 'application/json', [])
    : {
      'Accept': 'application/json',
      'Authorization': 'Bearer ' + settings.apiKey.trim(),
      'User-Agent': USER_AGENT
    };
  const options: http.HttpRequestOptions = {
    method: http.RequestMethod.GET,
    header: headers,
    connectTimeout: 15000,
    readTimeout: 30000,
    usingCache: false,
    expectDataType: http.HttpDataType.STRING
  };
  const request: http.HttpRequest = http.createHttp();
  try {
    const response: http.HttpResponse = await request.request(modelsUrl(baseUrl), options);
    const raw: string = response.result as string;
    if (response.responseCode < 200 || response.responseCode >= 300) {
      return {
        ok: false,
        models: [],
        message: httpErrorText(response.responseCode, raw)
      };
    }
    const envelope: ModelsEnvelope = JSON.parse(raw) as ModelsEnvelope;
    const list: string[] = [];
    if (envelope.data !== undefined) {
      for (let i = 0; i < envelope.data.length; i++) {
        const entry: ModelEntry = envelope.data[i];
        if (entry.id !== undefined && entry.id.length > 0 && list.indexOf(entry.id) < 0) {
          list.push(entry.id);
        }
      }
    }
    list.sort();
    if (list.length === 0) {
      return { ok: true, models: [], message: t('连接成功，但服务没有返回模型列表') };
    }
    return { ok: true, models: list, message: t('连接成功，发现 ') + list.length + t(' 个模型') };
  } catch (e) {
    const error: BusinessError = e as BusinessError;
    return { ok: false, models: [], message: describeNetworkError(error) };
  } finally {
    request.destroy();
  }
}
