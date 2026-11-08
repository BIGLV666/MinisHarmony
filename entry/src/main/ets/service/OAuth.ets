import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { AppSettings, cloneSettings } from '../core/Types';
import {
  CLAUDE_CLI_USER_AGENT,
  CLAUDE_OAUTH_BETAS,
  CODEX_CLIENT_ID,
  CODEX_REDIRECT_URI,
  CODEX_TOKEN_URL,
  COPILOT_ACCESS_TOKEN_URL,
  COPILOT_CLIENT_ID,
  COPILOT_DEVICE_CODE_URL,
  COPILOT_SCOPE,
  COPILOT_SESSION_TOKEN_URL,
  CopilotSession,
  CopilotStorage,
  DeviceAuthorization,
  DevicePollResult,
  JwtClaims,
  OAuthProvider,
  OAuthToken,
  RedirectCode,
  authorizeUrl,
  bumpedDeviceInterval,
  classifyDevicePoll,
  copilotStorageJson,
  extractRedirectCode,
  jwtClaimsFromPayloadJson,
  jwtPayloadSegment,
  maskToken,
  oauthStateFromBytes,
  parseCopilotSession,
  parseCopilotStorage,
  parseDeviceAuthorization,
  parseTokenJson,
  pkceChallengeFromDigest,
  pkceVerifierFromBytes,
  tokenFromJson,
  tokenJson,
  tokenNeedsRefresh
} from '../core/OAuth';
import { SecureStore } from './SecureStore';
import { t } from '../core/I18n';

const encoder: util.TextEncoder = new util.TextEncoder();
const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
const base64: util.Base64Helper = new util.Base64Helper();

const ALIAS_CLAUDE: string = 'MinisHarmony.oauth.claude';
const ALIAS_CODEX: string = 'MinisHarmony.oauth.codex';
const ALIAS_COPILOT: string = 'MinisHarmony.oauth.copilot';

const TOKEN_TIMEOUT_MS: number = 30000;

export interface ClaudeLoginStart {
  url: string;
  verifier: string;
  state: string;
}

export interface CopilotLoginStart {
  device: DeviceAuthorization;
}

export interface CodexLoginStart {
  url: string;
  verifier: string;
  state: string;
}

interface RawCodexToken {
  id_token?: string;
}

export interface OAuthOutcome {
  ok: boolean;
  message: string;
}

interface OAuthHttpResult extends OAuthOutcome {
  text: string;
}

function aliasFor(provider: OAuthProvider): string {
  if (provider === 'codex') {
    return ALIAS_CODEX;
  }
  if (provider === 'copilot') {
    return ALIAS_COPILOT;
  }
  return ALIAS_CLAUDE;
}

function decode(bytes: Uint8Array): string {
  return decoder.decodeToString(bytes);
}

function cliHeaders(): Record<string, string> {
  const headers: Record<string, string> = {
    'User-Agent': CLAUDE_CLI_USER_AGENT,
    'X-Stainless-Lang': 'js',
    'X-Stainless-Package-Version': '0.106.0',
    'X-Stainless-OS': 'Linux',
    'X-Stainless-Arch': 'arm64',
    'X-Stainless-Runtime': 'node',
    'X-Stainless-Runtime-Version': 'v24.18.0',
    'X-Stainless-Retry-Count': '0',
    'X-Stainless-Timeout': '600',
    'X-App': 'cli',
    'Anthropic-Dangerous-Direct-Browser-Access': 'true'
  };
  return headers;
}

/** Headers for an Anthropic Messages request made with an OAuth token. */
export function claudeOAuthRequestHeaders(): Record<string, string> {
  const headers: Record<string, string> = cliHeaders();
  headers['anthropic-beta'] = CLAUDE_OAUTH_BETAS.join(',');
  return headers;
}

async function postJson(
  url: string,
  body: string,
  extraHeaders: Record<string, string>
): Promise<OAuthHttpResult> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'Accept': 'application/json'
  };
  const keys: string[] = Object.keys(extraHeaders);
  for (let i = 0; i < keys.length; i++) {
    headers[keys[i]] = extraHeaders[keys[i]];
  }
  const options: http.HttpRequestOptions = {
    method: http.RequestMethod.POST,
    header: headers,
    extraData: body,
    connectTimeout: 20000,
    readTimeout: TOKEN_TIMEOUT_MS,
    expectDataType: http.HttpDataType.STRING,
    usingCache: false
  };
  const request: http.HttpRequest = http.createHttp();
  try {
    const response: http.HttpResponse = await request.request(url, options);
    const text: string = typeof response.result === 'string' ? response.result : '';
    if (response.responseCode < 200 || response.responseCode >= 300) {
      let detail: string = text;
      if (detail.length > 200) {
        detail = detail.substring(0, 200);
      }
      return {
        ok: false,
        message: t('登录失败：HTTP ') + response.responseCode.toString() +
          (detail.length > 0 ? t('（') + detail + t('）') : ''),
        text: text
      };
    }
    return { ok: true, message: '', text: text };
  } catch (e) {
    const error: Error = e as Error;
    return { ok: false, message: t('登录失败：') + error.message, text: '' };
  } finally {
    request.destroy();
  }
}

/** Token refresh endpoints accept form encoding; the code exchange is JSON. */
async function postForm(url: string, body: string): Promise<OAuthHttpResult> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/x-www-form-urlencoded',
    'Accept': 'application/json'
  };
  const options: http.HttpRequestOptions = {
    method: http.RequestMethod.POST,
    header: headers,
    extraData: body,
    connectTimeout: 20000,
    readTimeout: TOKEN_TIMEOUT_MS,
    expectDataType: http.HttpDataType.STRING,
    usingCache: false
  };
  const request: http.HttpRequest = http.createHttp();
  try {
    const response: http.HttpResponse = await request.request(url, options);
    const text: string = typeof response.result === 'string' ? response.result : '';
    if (response.responseCode < 200 || response.responseCode >= 300) {
      let detail: string = text;
      if (detail.length > 200) {
        detail = detail.substring(0, 200);
      }
      return {
        ok: false,
        message: t('刷新登录失败：HTTP ') + response.responseCode.toString() +
          (detail.length > 0 ? t('（') + detail + t('）') : ''),
        text: text
      };
    }
    return { ok: true, message: '', text: text };
  } catch (e) {
    const error: Error = e as Error;
    return { ok: false, message: t('刷新登录失败：') + error.message, text: '' };
  } finally {
    request.destroy();
  }
}

function formEncode(value: string): string {
  return encodeURIComponent(value);
}

async function delay(ms: number): Promise<void> {
  await new Promise<void>((resolve: (value: void) => void) => {
    setTimeout(() => resolve(), ms);
  });
}

/**
 * OAuth token lifecycle. Tokens live in the Asset Store under a per-provider
 * alias; only a masked form is ever shown in the UI. The in-memory copy makes
 * request-time lookups synchronous, and refresh is single-flight because the
 * providers rotate refresh tokens (two concurrent refreshes would invalidate
 * each other).
 */
export class OAuthService {
  private static claudeToken: OAuthToken | null = null;
  private static codexToken: OAuthToken | null = null;
  private static copilot: CopilotStorage | null = null;
  private static loaded: boolean = false;
  private static refreshing: Promise<string> | null = null;
  private static codexRefreshing: Promise<string> | null = null;
  private static copilotRefreshing: Promise<string> | null = null;

  static async init(): Promise<void> {
    if (OAuthService.loaded) {
      return;
    }
    OAuthService.loaded = true;
    const claude: string | null = await SecureStore.get(ALIAS_CLAUDE);
    if (claude !== null && claude.length > 0) {
      OAuthService.claudeToken = parseTokenJson(claude);
    }
    const codex: string | null = await SecureStore.get(ALIAS_CODEX);
    if (codex !== null && codex.length > 0) {
      OAuthService.codexToken = parseTokenJson(codex);
    }
    const copilot: string | null = await SecureStore.get(ALIAS_COPILOT);
    if (copilot !== null && copilot.length > 0) {
      OAuthService.copilot = parseCopilotStorage(copilot);
    }
  }

  static hasClaudeToken(): boolean {
    return OAuthService.claudeToken !== null;
  }

  static claudeMaskedToken(): string {
    const token: OAuthToken | null = OAuthService.claudeToken;
    return token === null ? '' : maskToken(token.accessToken);
  }

  static async forgetClaude(): Promise<void> {
    OAuthService.claudeToken = null;
    await SecureStore.remove(ALIAS_CLAUDE);
  }

  private static async saveClaude(token: OAuthToken): Promise<void> {
    OAuthService.claudeToken = token;
    await SecureStore.set(ALIAS_CLAUDE, tokenJson(token));
  }

  /** A valid token if one is cached and not near expiry, otherwise ''. */
  static cachedClaudeToken(): string {
    const token: OAuthToken | null = OAuthService.claudeToken;
    if (token === null) {
      return '';
    }
    if (tokenNeedsRefresh(token, Date.now())) {
      return '';
    }
    return token.accessToken;
  }

  /**
   * Returns a usable access token, refreshing it when close to expiry. Returns
   * '' when the user has not signed in or the refresh token was rejected.
   */
  static async validClaudeToken(): Promise<string> {
    const token: OAuthToken | null = OAuthService.claudeToken;
    if (token === null) {
      return '';
    }
    if (!tokenNeedsRefresh(token, Date.now())) {
      return token.accessToken;
    }
    if (OAuthService.refreshing !== null) {
      return OAuthService.refreshing;
    }
    OAuthService.refreshing = OAuthService.refreshClaude(token);
    try {
      return await OAuthService.refreshing;
    } finally {
      OAuthService.refreshing = null;
    }
  }

  private static async refreshClaude(stale: OAuthToken): Promise<string> {
    if (stale.refreshToken.length === 0) {
      return stale.accessToken;
    }
    const body: string = JSON.stringify({
      grant_type: 'refresh_token',
      client_id: '9d1c250a-e61b-44d9-88ed-5944d1962f5e',
      refresh_token: stale.refreshToken
    });
    const result: OAuthHttpResult = await postJson(
      'https://claude.ai/v1/oauth/token', body, cliHeaders());
    if (!result.ok) {
      // Keep the old token: a transient network failure must not log the user
      // out. The next request will try again.
      return stale.accessToken;
    }
    const fresh: OAuthToken | null = tokenFromJson(result.text, Date.now());
    if (fresh === null) {
      return stale.accessToken;
    }
    if (fresh.refreshToken.length === 0) {
      fresh.refreshToken = stale.refreshToken;
    }
    await OAuthService.saveClaude(fresh);
    return fresh.accessToken;
  }

  /**
   * Build the authorization URL and open the system browser. The verifier and
   * state stay in the sheet so the callback can be pasted back; nothing is
   * written until the exchange succeeds.
   */
  static async beginClaudeLogin(
    context: common.UIAbilityContext
  ): Promise<ClaudeLoginStart | null> {
    try {
      const random: cryptoFramework.Random = cryptoFramework.createRandom();
      const verifierBytes: Uint8Array = random.generateRandomSync(64).data;
      const verifier: string = pkceVerifierFromBytes(verifierBytes);
      const digest: Uint8Array = await OAuthService.sha256(verifier);
      const challenge: string = pkceChallengeFromDigest(digest);
      const state: string = oauthStateFromBytes(random.generateRandomSync(32).data);
      const url: string = authorizeUrl('claude', challenge, state);
      await context.openLink(url);
      return { url: url, verifier: verifier, state: state };
    } catch (e) {
      return null;
    }
  }

  /**
   * Exchange the pasted callback for a token. Accepts a full redirect URL, a
   * `code#state` pair or a bare code.
   */
  static async completeClaudeLogin(
    verifier: string,
    expectedState: string,
    pasted: string
  ): Promise<OAuthOutcome> {
    const parsed: RedirectCode | null = extractRedirectCode(pasted);
    if (parsed === null) {
      return { ok: false, message: t('没有识别到授权码，请粘贴浏览器地址栏中的回调地址或授权码') };
    }
    if (parsed.state.length > 0 && expectedState.length > 0 &&
      parsed.state !== expectedState) {
      return { ok: false, message: t('授权状态不匹配，请重新发起登录') };
    }
    const body: string = JSON.stringify({
      grant_type: 'authorization_code',
      client_id: '9d1c250a-e61b-44d9-88ed-5944d1962f5e',
      code: parsed.code,
      redirect_uri: 'http://localhost:54545/callback',
      code_verifier: verifier,
      state: parsed.state.length > 0 ? parsed.state : expectedState
    });
    const result: OAuthHttpResult = await postJson(
      'https://claude.ai/v1/oauth/token', body, cliHeaders());
    if (!result.ok) {
      return result;
    }
    const token: OAuthToken | null = tokenFromJson(result.text, Date.now());
    if (token === null) {
      return { ok: false, message: t('登录响应缺少 access_token') };
    }
    await OAuthService.saveClaude(token);
    return { ok: true, message: t('已使用 Claude 账号登录') };
  }

  // MARK: - ChatGPT Codex (PKCE, Responses API)

  static hasCodexToken(): boolean {
    return OAuthService.codexToken !== null;
  }

  static codexMaskedToken(): string {
    const token: OAuthToken | null = OAuthService.codexToken;
    return token === null ? '' : maskToken(token.accessToken);
  }

  static codexPlan(): string {
    const token: OAuthToken | null = OAuthService.codexToken;
    return token === null ? '' : token.planType;
  }

  static codexAccountId(): string {
    const token: OAuthToken | null = OAuthService.codexToken;
    return token === null ? '' : token.accountId;
  }

  static async forgetCodex(): Promise<void> {
    OAuthService.codexToken = null;
    await SecureStore.remove(ALIAS_CODEX);
  }

  private static async saveCodex(token: OAuthToken): Promise<void> {
    OAuthService.codexToken = token;
    await SecureStore.set(ALIAS_CODEX, tokenJson(token));
  }

  /**
   * Same PKCE start as Claude: open the system browser and keep the verifier
   * and state in the sheet. The Codex redirect points at localhost:1455, which
   * nothing listens on, so the user copies the callback URL back.
   */
  static async beginCodexLogin(
    context: common.UIAbilityContext
  ): Promise<CodexLoginStart | null> {
    try {
      const random: cryptoFramework.Random = cryptoFramework.createRandom();
      const verifier: string = pkceVerifierFromBytes(random.generateRandomSync(64).data);
      const digest: Uint8Array = await OAuthService.sha256(verifier);
      const challenge: string = pkceChallengeFromDigest(digest);
      const state: string = oauthStateFromBytes(random.generateRandomSync(32).data);
      const url: string = authorizeUrl('codex', challenge, state);
      if (url.length === 0) {
        return null;
      }
      await context.openLink(url);
      return { url: url, verifier: verifier, state: state };
    } catch (e) {
      return null;
    }
  }

  static async completeCodexLogin(
    verifier: string,
    expectedState: string,
    pasted: string
  ): Promise<OAuthOutcome> {
    const parsed: RedirectCode | null = extractRedirectCode(pasted);
    if (parsed === null) {
      return { ok: false, message: t('没有识别到授权码，请粘贴浏览器地址栏中的回调地址或授权码') };
    }
    if (parsed.state.length > 0 && expectedState.length > 0 &&
      parsed.state !== expectedState) {
      return { ok: false, message: t('授权状态不匹配，请重新发起登录') };
    }
    const body: string = JSON.stringify({
      grant_type: 'authorization_code',
      client_id: CODEX_CLIENT_ID,
      code: parsed.code,
      redirect_uri: CODEX_REDIRECT_URI,
      code_verifier: verifier
    });
    const result: OAuthHttpResult = await postJson(CODEX_TOKEN_URL, body, {});
    if (!result.ok) {
      return result;
    }
    const token: OAuthToken | null = tokenFromJson(result.text, Date.now());
    if (token === null) {
      return { ok: false, message: t('登录响应缺少 access_token') };
    }
    OAuthService.applyCodexClaims(token, result.text);
    await OAuthService.saveCodex(token);
    return { ok: true, message: t('已使用 ChatGPT 账号登录') };
  }

  /** Account id and plan live in the id_token; decode, never verify. */
  private static applyCodexClaims(token: OAuthToken, rawJson: string): void {
    let raw: RawCodexToken;
    try {
      raw = JSON.parse(rawJson) as RawCodexToken;
    } catch (e) {
      return;
    }
    if (raw === null || raw === undefined || typeof raw.id_token !== 'string' ||
      raw.id_token.length === 0) {
      return;
    }
    const claims: JwtClaims = OAuthService.jwtClaims(raw.id_token);
    token.accountId = claims.chatgptAccountId;
    token.planType = claims.chatgptPlanType;
  }

  static async validCodexToken(): Promise<string> {
    const token: OAuthToken | null = OAuthService.codexToken;
    if (token === null) {
      return '';
    }
    if (!tokenNeedsRefresh(token, Date.now())) {
      return token.accessToken;
    }
    if (OAuthService.codexRefreshing !== null) {
      return OAuthService.codexRefreshing;
    }
    OAuthService.codexRefreshing = OAuthService.refreshCodex(token);
    try {
      return await OAuthService.codexRefreshing;
    } finally {
      OAuthService.codexRefreshing = null;
    }
  }

  private static async refreshCodex(stale: OAuthToken): Promise<string> {
    if (stale.refreshToken.length === 0) {
      return stale.accessToken;
    }
    const body: string = 'grant_type=refresh_token' +
      '&client_id=' + formEncode(CODEX_CLIENT_ID) +
      '&refresh_token=' + formEncode(stale.refreshToken);
    const result: OAuthHttpResult = await postForm(CODEX_TOKEN_URL, body);
    if (!result.ok) {
      // Keep the old token: a transient network failure must not sign out.
      return stale.accessToken;
    }
    const fresh: OAuthToken | null = tokenFromJson(result.text, Date.now());
    if (fresh === null) {
      return stale.accessToken;
    }
    if (fresh.refreshToken.length === 0) {
      fresh.refreshToken = stale.refreshToken;
    }
    fresh.accountId = stale.accountId;
    fresh.planType = stale.planType;
    OAuthService.applyCodexClaims(fresh, result.text);
    await OAuthService.saveCodex(fresh);
    return fresh.accessToken;
  }

  // MARK: - GitHub Copilot (RFC 8628 device flow)

  static hasCopilotToken(): boolean {
    return OAuthService.copilot !== null;
  }

  static copilotMaskedToken(): string {
    const storage: CopilotStorage | null = OAuthService.copilot;
    return storage === null ? '' : maskToken(storage.githubToken);
  }

  static async forgetCopilot(): Promise<void> {
    OAuthService.copilot = null;
    await SecureStore.remove(ALIAS_COPILOT);
  }

  /**
   * Ask GitHub for a device code and open the verification page. The caller
   * shows `userCode`, then calls `pollCopilotLogin`.
   */
  static async beginCopilotLogin(
    context: common.UIAbilityContext
  ): Promise<CopilotLoginStart | null> {
    const body: string = JSON.stringify({
      client_id: COPILOT_CLIENT_ID,
      scope: COPILOT_SCOPE
    });
    const result: OAuthHttpResult = await postJson(
      COPILOT_DEVICE_CODE_URL, body, {});
    if (!result.ok) {
      return null;
    }
    const device: DeviceAuthorization | null = parseDeviceAuthorization(result.text);
    if (device === null) {
      return null;
    }
    if (device.verificationUri.length > 0) {
      try {
        await context.openLink(device.verificationUri);
      } catch (e) {
        // The code is still shown; the user can open the URL manually.
      }
    }
    return { device: device };
  }

  /** Poll until GitHub says the device was authorised, the code expires, etc. */
  static async pollCopilotLogin(device: DeviceAuthorization): Promise<OAuthOutcome> {
    let interval: number = device.interval;
    const deadline: number = Date.now() + device.expiresIn * 1000;
    while (Date.now() < deadline) {
      await delay(interval * 1000);
      const body: string = JSON.stringify({
        client_id: COPILOT_CLIENT_ID,
        device_code: device.deviceCode,
        grant_type: 'urn:ietf:params:oauth:grant-type:device_code'
      });
      const result: OAuthHttpResult = await postJson(
        COPILOT_ACCESS_TOKEN_URL, body, {});
      const poll: DevicePollResult = classifyDevicePoll(result.text, result.ok);
      if (poll.kind === 'success') {
        const storage: CopilotStorage = {
          githubToken: poll.accessToken,
          sessionToken: '',
          sessionExpiresAt: 0
        };
        OAuthService.copilot = storage;
        await SecureStore.set(ALIAS_COPILOT, copilotStorageJson(storage));
        return { ok: true, message: t('已使用 GitHub Copilot 账号登录') };
      }
      if (poll.kind === 'pending') {
        continue;
      }
      if (poll.kind === 'slow_down') {
        interval = bumpedDeviceInterval(interval);
        continue;
      }
      return { ok: false, message: poll.message };
    }
    return { ok: false, message: t('设备码已过期，请重新登录') };
  }

  /** The short-lived token Copilot's chat API actually accepts. */
  static async validCopilotSessionToken(): Promise<string> {
    const storage: CopilotStorage | null = OAuthService.copilot;
    if (storage === null) {
      return '';
    }
    if (storage.sessionToken.length > 0 &&
      storage.sessionExpiresAt - Date.now() > 60 * 1000) {
      return storage.sessionToken;
    }
    if (OAuthService.copilotRefreshing !== null) {
      return OAuthService.copilotRefreshing;
    }
    OAuthService.copilotRefreshing = OAuthService.exchangeCopilotSession(storage);
    try {
      return await OAuthService.copilotRefreshing;
    } finally {
      OAuthService.copilotRefreshing = null;
    }
  }

  private static async exchangeCopilotSession(
    storage: CopilotStorage
  ): Promise<string> {
    const headers: Record<string, string> = {
      'Accept': 'application/json',
      'Authorization': 'token ' + storage.githubToken,
      'User-Agent': 'GitHubCopilotChat/0.31.0',
      'Editor-Version': 'vscode/1.104.0',
      'Editor-Plugin-Version': 'copilot-chat/0.31.0',
      'X-GitHub-Api-Version': '2025-04-01'
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: 20000,
      readTimeout: 30000,
      expectDataType: http.HttpDataType.STRING,
      usingCache: false
    };
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse =
        await request.request(COPILOT_SESSION_TOKEN_URL, options);
      const text: string = typeof response.result === 'string' ? response.result : '';
      if (response.responseCode < 200 || response.responseCode >= 300) {
        return '';
      }
      const session: CopilotSession | null = parseCopilotSession(text, Date.now());
      if (session === null) {
        return '';
      }
      const next: CopilotStorage = {
        githubToken: storage.githubToken,
        sessionToken: session.token,
        sessionExpiresAt: session.expiresAt
      };
      OAuthService.copilot = next;
      await SecureStore.set(ALIAS_COPILOT, copilotStorageJson(next));
      return session.token;
    } catch (e) {
      return '';
    } finally {
      request.destroy();
    }
  }

  /** Fill the runtime-only OAuth fields the request builders read. */
  static async decorate(settings: AppSettings): Promise<AppSettings> {
    const copy: AppSettings = cloneSettings(settings);
    if (copy.preset === 'anthropic') {
      const token: string = await OAuthService.validClaudeToken();
      if (token.length > 0) {
        copy.oauthToken = token;
      }
    } else if (copy.preset === 'codex') {
      const token: string = await OAuthService.validCodexToken();
      if (token.length > 0) {
        copy.oauthToken = token;
        const stored: OAuthToken | null = OAuthService.codexToken;
        copy.oauthAccountId = stored !== null ? stored.accountId : '';
      }
    } else if (copy.preset === 'copilot') {
      const token: string = await OAuthService.validCopilotSessionToken();
      if (token.length > 0) {
        copy.oauthToken = token;
      }
    }
    return copy;
  }

  /** Synchronous variant for paths that already ran `decorate`. */
  static cachedTokenFor(settings: AppSettings): string {
    if (settings.preset !== 'anthropic') {
      return '';
    }
    return OAuthService.cachedClaudeToken();
  }

  private static async sha256(value: string): Promise<Uint8Array> {
    const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
    await md.update({ data: encoder.encodeInto(value) });
    const digest: cryptoFramework.DataBlob = await md.digest();
    return digest.data;
  }

  /** Decode a Codex id_token payload; exported for the future login flow. */
  static jwtClaims(idToken: string): JwtClaims {
    const segment: string = jwtPayloadSegment(idToken);
    if (segment.length === 0) {
      return jwtClaimsFromPayloadJson('{}');
    }
    try {
      let padded: string = segment.replace(/-/g, '+').replace(/_/g, '/');
      while (padded.length % 4 !== 0) {
        padded += '=';
      }
      const bytes: Uint8Array = base64.decodeSync(padded);
      return jwtClaimsFromPayloadJson(decode(bytes));
    } catch (e) {
      return jwtClaimsFromPayloadJson('{}');
    }
  }
}
