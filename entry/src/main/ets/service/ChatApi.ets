import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { AppSettings, ChatMessage } from '../core/Types';
import { soulPrompt } from '../core/Soul';
import { capsForModel, clampMaxTokens } from '../core/ModelCaps';
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

const USER_AGENT: string = 'MinisHarmony/1.0 (HarmonyOS tablet)';

export interface ChatCallbacks {
  onDelta: (content: string, reasoning: string, toolCalls: ToolCallDelta[]) => void;
  onUsage: (usage: TokenUsage) => void;
  onDone: (finishReason: string) => void;
  onError: (message: string) => void;
}

interface ApiToolFunctionDefinition {
  name: string;
  description: string;
  parameters: ToolParameters;
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
  max_tokens?: number;
  /** Only sent when the user opted into thinking via /thinking. */
  reasoning_effort?: string;
  tools?: ApiToolDefinition[];
  tool_choice?: string;
}

interface ModelEntry {
  id?: string;
}

interface ModelsEnvelope {
  data?: ModelEntry[];
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

export interface SummaryResult {
  ok: boolean;
  text: string;
  message: string;
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
  return '网络请求失败（' + error.code + '）：' + error.message;
}

function httpErrorText(code: number, body: string): string {
  const detail: string = parseErrorMessage(body);
  let prefix: string = '请求失败（HTTP ' + code + '）';
  if (code === 400) {
    prefix = '请求参数被拒绝（HTTP 400）';
  } else if (code === 401) {
    prefix = 'API Key 无效或未被授权（HTTP 401）';
  } else if (code === 402) {
    prefix = 'OpenCode Go 订阅额度不足（HTTP 402）';
  } else if (code === 403) {
    prefix = '当前账号或区域无权访问该模型（HTTP 403）';
  } else if (code === 404) {
    prefix = '接口地址或模型不存在（HTTP 404）';
  } else if (code === 429) {
    prefix = '请求过于频繁，请稍后重试（HTTP 429）';
  } else if (code >= 500) {
    prefix = '服务端暂时不可用（HTTP ' + code + '）';
  }
  return detail.length > 0 ? prefix + '：' + detail : prefix;
}

function buildMessages(
  settings: AppSettings,
  history: ChatMessage[],
  memoryContext: string,
  resolveImage: ImageResolver | null
): ApiMessage[] {
  const messages: ApiMessage[] = toApiMessages(history, resolveImage);
  let systemPrompt: string = settings.systemPrompt.trim();
  const soul: string = soulPrompt(settings.soulId).trim();
  if (soul.length > 0) {
    systemPrompt = systemPrompt.length > 0
      ? soul + '\n\n' + systemPrompt
      : soul;
  }
  const memory: string = memoryContext.trim();
  if (memory.length > 0) {
    systemPrompt = systemPrompt.length > 0
      ? systemPrompt + '\n\n' + memory
      : memory;
  }
  if (systemPrompt.length > 0) {
    messages.unshift({ role: 'system', content: systemPrompt });
  }
  return messages;
}

function buildToolDefinitions(tools: ToolDefinition[]): ApiToolDefinition[] {
  const definitions: ApiToolDefinition[] = [];
  for (let i = 0; i < tools.length; i++) {
    definitions.push({
      type: 'function',
      function: {
        name: tools[i].name,
        description: tools[i].description,
        parameters: tools[i].parameters
      }
    });
  }
  return definitions;
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
    callbacks.onError('请先在设置中填写 API 地址');
    return handle;
  }
  if (apiKey.length === 0) {
    callbacks.onError('请先在设置中填写 API Key');
    return handle;
  }

  const body: ChatRequestBody = {
    model: settings.modelId,
    messages: buildMessages(settings, history, memoryContext, resolveImage),
    stream: true,
    stream_options: { include_usage: true },
    temperature: settings.temperature,
    max_tokens: clampMaxTokens(settings.maxTokens, capsForModel(settings.modelId))
  };
  if (settings.thinkingLevel !== 'off') {
    body.reasoning_effort = settings.thinkingLevel;
  }
  if (tools.length > 0) {
    body.tools = buildToolDefinitions(tools);
    body.tool_choice = 'auto';
  }

  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'Accept': 'text/event-stream',
    'Authorization': 'Bearer ' + apiKey,
    'User-Agent': USER_AGENT
  };
  if (shouldAttachSessionHeader(baseUrl, sessionId)) {
    headers[OPENCODE_SESSION_HEADER] = sessionId;
  }

  const options: http.HttpRequestOptions = {
    method: http.RequestMethod.POST,
    header: headers,
    extraData: JSON.stringify(body),
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
    const delta: DeltaResult = parseOpenAiData(event.data);
    if (delta.error.length > 0) {
      streamError = delta.error;
      return;
    }
    if (delta.content.length > 0 || delta.reasoning.length > 0 ||
      delta.toolCalls.length > 0) {
      callbacks.onDelta(delta.content, delta.reasoning, delta.toolCalls);
    }
    if (delta.usage.present) {
      callbacks.onUsage(delta.usage);
    }
    if (delta.finishReason.length > 0) {
      finishReason = delta.finishReason;
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
    request.requestInStream(chatCompletionsUrl(baseUrl), options, (err: BusinessError, code: number) => {
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
    fail('无法发起请求：' + error.message);
  }

  return handle;
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
  const baseUrl: string = normalizeBaseUrl(settings.baseUrl);
  const apiKey: string = settings.apiKey.trim();
  if (baseUrl.length === 0) {
    return { ok: false, text: '', message: '请先在设置中填写 API 地址' };
  }
  if (apiKey.length === 0) {
    return { ok: false, text: '', message: '请先在设置中填写 API Key' };
  }
  if (transcript.trim().length === 0) {
    return { ok: false, text: '', message: '没有可压缩的内容' };
  }

  const body: SummaryRequestBody = {
    model: settings.modelId,
    messages: [
      {
        role: 'system',
        content: '你是对话压缩器。把给出的对话压缩成简洁的中文摘要，保留：' +
          '用户目标与约束、已确认的事实与决定、改过的文件与命令、未完成事项。' +
          '不要编造，不要加开场白，直接输出摘要正文。'
      },
      {
        role: 'user',
        content: transcript
      }
    ],
    stream: false,
    temperature: 0.2,
    max_tokens: 1500
  };

  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Authorization': 'Bearer ' + apiKey,
    'User-Agent': USER_AGENT
  };
  if (shouldAttachSessionHeader(baseUrl, sessionId)) {
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
      return { ok: false, text: '', message: '模型没有返回摘要' };
    }
    const choice: SummaryChoice = envelope.choices[0];
    if (choice.message === undefined || choice.message.content === undefined) {
      return { ok: false, text: '', message: '模型没有返回摘要' };
    }
    const text: string = choice.message.content.trim();
    if (text.length === 0) {
      return { ok: false, text: '', message: '模型返回了空摘要' };
    }
    return { ok: true, text: text, message: '已生成摘要' };
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
export async function fetchModelIds(settings: AppSettings): Promise<ModelsResult> {
  const baseUrl: string = normalizeBaseUrl(settings.baseUrl);
  if (baseUrl.length === 0) {
    return { ok: false, models: [], message: '请先填写 API 地址' };
  }
  const headers: Record<string, string> = {
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
      return { ok: true, models: [], message: '连接成功，但服务没有返回模型列表' };
    }
    return { ok: true, models: list, message: '连接成功，发现 ' + list.length + ' 个模型' };
  } catch (e) {
    const error: BusinessError = e as BusinessError;
    return { ok: false, models: [], message: describeNetworkError(error) };
  } finally {
    request.destroy();
  }
}
