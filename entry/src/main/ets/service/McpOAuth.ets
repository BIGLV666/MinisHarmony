import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { McpServerConfig } from '../core/McpProtocol';
import {
  McpOAuthConfig,
  McpOAuthLoginStart,
  McpOAuthOutcome,
  buildMcpAuthorizeUrl,
  effectiveRedirectUri,
  effectiveResource,
  isMcpOAuthConfigured,
  mcpRefreshBody,
  mcpTokenExchangeBody
} from '../core/McpOAuth';
import {
  OAuthToken,
  RedirectCode,
  extractRedirectCode,
  maskToken,
  oauthStateFromBytes,
  parseTokenJson,
  pkceChallengeFromDigest,
  pkceVerifierFromBytes,
  tokenFromJson,
  tokenJson,
  tokenNeedsRefresh
} from '../core/OAuth';
import { SecureStore } from './SecureStore';

const encoder: util.TextEncoder = new util.TextEncoder();
const TOKEN_TIMEOUT_MS: number = 30000;

interface McpOAuthHttpResult extends McpOAuthOutcome {
  text: string;
}

async function postForm(url: string, body: string): Promise<McpOAuthHttpResult> {
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
        message: 'MCP OAuth 失败：HTTP ' + response.responseCode.toString() +
          (detail.length > 0 ? '（' + detail + '）' : ''),
        text: text
      };
    }
    return { ok: true, message: '', text: text };
  } catch (e) {
    const error: Error = e as Error;
    return { ok: false, message: 'MCP OAuth 失败：' + error.message, text: '' };
  } finally {
    request.destroy();
  }
}

async function sha256(value: string): Promise<Uint8Array> {
  const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
  await md.update({ data: encoder.encodeInto(value) });
  const digest: cryptoFramework.DataBlob = await md.digest();
  return digest.data;
}

/**
 * Per-server MCP OAuth state. Non-secret configuration lives in
 * `McpServerConfig.oauth`; the client secret and issued tokens live in the
 * Asset Store under aliases namespaced by the server id (the Android
 * implementation keeps them in EncryptedSharedPreferences). Nothing in this
 * class logs a secret.
 */
export class McpOAuthService {
  private static tokens: Map<string, OAuthToken | null> = new Map();
  private static loaded: Set<string> = new Set();
  private static refreshing: Map<string, Promise<string>> = new Map();

  private static tokenAlias(serverId: string): string {
    return 'MinisHarmony.mcp.oauth.token.' + serverId;
  }

  private static secretAlias(serverId: string): string {
    return 'MinisHarmony.mcp.oauth.secret.' + serverId;
  }

  private static async load(serverId: string): Promise<OAuthToken | null> {
    if (McpOAuthService.loaded.has(serverId)) {
      const cached: OAuthToken | null | undefined = McpOAuthService.tokens.get(serverId);
      return cached === undefined ? null : cached;
    }
    const raw: string | null = await SecureStore.get(McpOAuthService.tokenAlias(serverId));
    if (raw === null) {
      // Asset Store unavailable right now; do not cache a negative result.
      return null;
    }
    const token: OAuthToken | null = raw.length > 0 ? parseTokenJson(raw) : null;
    McpOAuthService.tokens.set(serverId, token);
    McpOAuthService.loaded.add(serverId);
    return token;
  }

  private static async saveToken(serverId: string, token: OAuthToken): Promise<void> {
    McpOAuthService.tokens.set(serverId, token);
    McpOAuthService.loaded.add(serverId);
    await SecureStore.set(McpOAuthService.tokenAlias(serverId), tokenJson(token));
  }

  static async hasToken(serverId: string): Promise<boolean> {
    return (await McpOAuthService.load(serverId)) !== null;
  }

  static async maskedToken(serverId: string): Promise<string> {
    const token: OAuthToken | null = await McpOAuthService.load(serverId);
    return token === null ? '' : maskToken(token.accessToken);
  }

  static async hasClientSecret(serverId: string): Promise<boolean> {
    const secret: string | null =
      await SecureStore.get(McpOAuthService.secretAlias(serverId));
    return secret !== null && secret.length > 0;
  }

  /** Empty removes the stored secret. Never echoes it back. */
  static async setClientSecret(serverId: string, secret: string): Promise<void> {
    await SecureStore.set(McpOAuthService.secretAlias(serverId), secret.trim());
  }

  /**
   * A bearer token to attach to MCP requests, refreshed when it is close to
   * expiry. Returns '' when no login is present (the server may still work
   * with static headers).
   */
  static async validToken(server: McpServerConfig): Promise<string> {
    if (!isMcpOAuthConfigured(server.oauth)) {
      return '';
    }
    const token: OAuthToken | null = await McpOAuthService.load(server.id);
    if (token === null) {
      return '';
    }
    if (!tokenNeedsRefresh(token, Date.now())) {
      return token.accessToken;
    }
    if (token.refreshToken.length === 0 ||
      server.oauth.tokenEndpoint.length === 0) {
      return token.accessToken;
    }
    const running: Promise<string> | undefined =
      McpOAuthService.refreshing.get(server.id);
    if (running !== undefined) {
      return running;
    }
    const task: Promise<string> = McpOAuthService.refresh(server, token);
    McpOAuthService.refreshing.set(server.id, task);
    try {
      return await task;
    } finally {
      McpOAuthService.refreshing.delete(server.id);
    }
  }

  private static async refresh(
    server: McpServerConfig,
    stale: OAuthToken
  ): Promise<string> {
    const storedSecret: string | null =
      await SecureStore.get(McpOAuthService.secretAlias(server.id));
    const secret: string = storedSecret !== null ? storedSecret : '';
    const body: string = mcpRefreshBody(
      stale.refreshToken,
      server.oauth.clientId,
      secret,
      effectiveResource(server.oauth, server.url)
    );
    const result: McpOAuthHttpResult =
      await postForm(server.oauth.tokenEndpoint, body);
    if (!result.ok) {
      // A transient failure must not sign the user out; the next call retries.
      return stale.accessToken;
    }
    const fresh: OAuthToken | null = tokenFromJson(result.text, Date.now());
    if (fresh === null) {
      return stale.accessToken;
    }
    if (fresh.refreshToken.length === 0) {
      fresh.refreshToken = stale.refreshToken;
    }
    await McpOAuthService.saveToken(server.id, fresh);
    return fresh.accessToken;
  }

  /**
   * Build the authorize URL and open the system browser. HarmonyOS has no
   * loopback listener, so the caller shows the URL and asks the user to paste
   * the callback back (same pattern as the Claude/Codex logins).
   */
  static async beginLogin(
    context: common.UIAbilityContext,
    server: McpServerConfig
  ): Promise<McpOAuthLoginStart | null> {
    const config: McpOAuthConfig = server.oauth;
    if (!isMcpOAuthConfigured(config)) {
      return null;
    }
    try {
      const random: cryptoFramework.Random = cryptoFramework.createRandom();
      const verifier: string =
        pkceVerifierFromBytes(random.generateRandomSync(64).data);
      const challenge: string = pkceChallengeFromDigest(await sha256(verifier));
      const state: string = oauthStateFromBytes(random.generateRandomSync(32).data);
      const url: string = buildMcpAuthorizeUrl(
        config.authorizationEndpoint,
        config.clientId,
        effectiveRedirectUri(config),
        challenge,
        state,
        effectiveResource(config, server.url),
        config.scopes
      );
      await context.openLink(url);
      return { url: url, verifier: verifier, state: state };
    } catch (e) {
      return null;
    }
  }

  static async completeLogin(
    server: McpServerConfig,
    verifier: string,
    expectedState: string,
    pasted: string
  ): Promise<McpOAuthOutcome> {
    const config: McpOAuthConfig = server.oauth;
    if (!isMcpOAuthConfigured(config)) {
      return { ok: false, message: '请先填写 Client ID 和授权/令牌端点' };
    }
    const parsed: RedirectCode | null = extractRedirectCode(pasted);
    if (parsed === null) {
      return { ok: false, message: '没有识别到授权码，请粘贴浏览器地址栏中的回调地址或授权码' };
    }
    if (parsed.state.length > 0 && expectedState.length > 0 &&
      parsed.state !== expectedState) {
      return { ok: false, message: '授权状态不匹配，请重新发起登录' };
    }
    const storedSecret: string | null =
      await SecureStore.get(McpOAuthService.secretAlias(server.id));
    const secret: string = storedSecret !== null ? storedSecret : '';
    const body: string = mcpTokenExchangeBody(
      parsed.code,
      effectiveRedirectUri(config),
      config.clientId,
      verifier,
      secret,
      effectiveResource(config, server.url)
    );
    const result: McpOAuthHttpResult =
      await postForm(config.tokenEndpoint, body);
    if (!result.ok) {
      return { ok: false, message: result.message };
    }
    const token: OAuthToken | null = tokenFromJson(result.text, Date.now());
    if (token === null) {
      return { ok: false, message: '登录响应缺少 access_token' };
    }
    await McpOAuthService.saveToken(server.id, token);
    const name: string = server.name.length > 0 ? server.name : server.url;
    return { ok: true, message: '已授权 MCP 服务「' + name + '」' };
  }

  /** Forget the tokens but keep the client secret (re-auth later). */
  static async signOut(serverId: string): Promise<void> {
    McpOAuthService.tokens.set(serverId, null);
    McpOAuthService.loaded.add(serverId);
    await SecureStore.remove(McpOAuthService.tokenAlias(serverId));
  }

  /** Forget tokens and the client secret; called when a server is deleted. */
  static async purge(serverId: string): Promise<void> {
    McpOAuthService.tokens.delete(serverId);
    McpOAuthService.loaded.delete(serverId);
    await SecureStore.remove(McpOAuthService.tokenAlias(serverId));
    await SecureStore.remove(McpOAuthService.secretAlias(serverId));
  }
}
