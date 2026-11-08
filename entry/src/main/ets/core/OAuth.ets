import { t } from './I18n';
/**
 * OAuth 2.0 (PKCE) and RFC 8628 device-flow helpers shared by the provider
 * logins. Everything here is pure: randomness and SHA-256 come from the
 * platform crypto kit in `service/OAuth.ets`, so the URL/query/JSON handling
 * can be tested without a device.
 *
 * The three providers ship fixed public client ids, exactly like the reference
 * client, because these are first-party CLI identities rather than credentials
 * issued to this app. They are not secrets; the tokens they produce are, and
 * those never leave the Asset Store.
 */

export type OAuthProvider = 'claude' | 'copilot' | 'codex';

export interface OAuthProviderConfig {
  id: OAuthProvider;
  label: string;
  authorizeUrl: string;
  tokenUrl: string;
  clientId: string;
  scopes: string;
  redirectUri: string;
  /** Extra query parameters appended after the standard PKCE ones. */
  extraAuthParams: string;
}

export const CLAUDE_CLIENT_ID: string = '9d1c250a-e61b-44d9-88ed-5944d1962f5e';
export const CLAUDE_AUTHORIZE_URL: string = 'https://claude.ai/oauth/authorize';
export const CLAUDE_TOKEN_URL: string = 'https://claude.ai/v1/oauth/token';
export const CLAUDE_REDIRECT_URI: string = 'http://localhost:54545/callback';
export const CLAUDE_SCOPES: string =
  'org:create_api_key user:profile user:inference user:sessions:claude_code ' +
  'user:mcp_servers user:file_upload';

export const COPILOT_DEVICE_CODE_URL: string = 'https://github.com/login/device/code';
export const COPILOT_ACCESS_TOKEN_URL: string = 'https://github.com/login/oauth/access_token';
export const COPILOT_SESSION_TOKEN_URL: string =
  'https://api.github.com/copilot_internal/v2/token';
export const COPILOT_CLIENT_ID: string = 'Iv1.b507a08c87ecfe98';
export const COPILOT_SCOPE: string = 'read:user';
export const COPILOT_API_BASE: string = 'https://api.githubcopilot.com';

export const CODEX_CLIENT_ID: string = 'app_EMoamEEZ73f0CkXaXp7hrann';
export const CODEX_AUTHORIZE_URL: string = 'https://auth.openai.com/oauth/authorize';
export const CODEX_TOKEN_URL: string = 'https://auth.openai.com/oauth/token';
export const CODEX_REDIRECT_URI: string = 'http://localhost:1455/auth/callback';
export const CODEX_SCOPES: string = 'openid profile email offline_access';

/** Refresh this long before the recorded expiry. */
export const OAUTH_REFRESH_BUFFER_MS: number = 5 * 60 * 1000;
/** Used when a token response omits `expires_in` (no proactive refresh). */
export const OAUTH_UNKNOWN_EXPIRY_MS: number = 0;

/**
 * The Claude CLI request profile. Anthropic gates OAuth credentials on the
 * `anthropic-beta` set and on sounding like the official CLI; the token
 * endpoint is behind the same bot check, so both paths share one table.
 */
export const CLAUDE_OAUTH_BETAS: string[] = [
  'claude-code-20250219',
  'oauth-2025-04-20',
  'interleaved-thinking-2025-05-14',
  'prompt-caching-scope-2026-01-05',
  'effort-2025-11-24',
  'context-management-2025-06-27',
  'extended-cache-ttl-2025-04-11'
];

export const CLAUDE_CLI_USER_AGENT: string = 'claude-cli/2.1.280 (external, cli)';

export interface OAuthToken {
  accessToken: string;
  refreshToken: string;
  /** Unix ms; 0 means the response carried no `expires_in`. */
  expiresAt: number;
  /** From the Codex id_token; empty for the other providers. */
  accountId: string;
  planType: string;
  lastRefresh: number;
}

export interface RedirectCode {
  code: string;
  state: string;
}

export interface JwtClaims {
  chatgptAccountId: string;
  chatgptPlanType: string;
  email: string;
}

const BASE64URL_ALPHABET: string =
  'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/** RFC 4648 §5 encoding without padding. */
export function base64UrlEncode(bytes: Uint8Array): string {
  let out: string = '';
  let i: number = 0;
  while (i + 2 < bytes.length) {
    const n: number = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    out += BASE64URL_ALPHABET.charAt((n >> 18) & 63);
    out += BASE64URL_ALPHABET.charAt((n >> 12) & 63);
    out += BASE64URL_ALPHABET.charAt((n >> 6) & 63);
    out += BASE64URL_ALPHABET.charAt(n & 63);
    i += 3;
  }
  const rest: number = bytes.length - i;
  if (rest === 1) {
    const n: number = bytes[i] << 16;
    out += BASE64URL_ALPHABET.charAt((n >> 18) & 63);
    out += BASE64URL_ALPHABET.charAt((n >> 12) & 63);
  } else if (rest === 2) {
    const n: number = (bytes[i] << 16) | (bytes[i + 1] << 8);
    out += BASE64URL_ALPHABET.charAt((n >> 18) & 63);
    out += BASE64URL_ALPHABET.charAt((n >> 12) & 63);
    out += BASE64URL_ALPHABET.charAt((n >> 6) & 63);
  }
  return out;
}

/** 64 random bytes make a 86-character RFC 7636 verifier. */
export function pkceVerifierFromBytes(bytes: Uint8Array): string {
  return base64UrlEncode(bytes);
}

export function pkceChallengeFromDigest(digest: Uint8Array): string {
  return base64UrlEncode(digest);
}

export function oauthStateFromBytes(bytes: Uint8Array): string {
  return base64UrlEncode(bytes);
}

export function providerConfig(provider: OAuthProvider): OAuthProviderConfig {
  if (provider === 'copilot') {
    return {
      id: 'copilot',
      label: 'GitHub Copilot',
      authorizeUrl: COPILOT_DEVICE_CODE_URL,
      tokenUrl: COPILOT_ACCESS_TOKEN_URL,
      clientId: COPILOT_CLIENT_ID,
      scopes: COPILOT_SCOPE,
      redirectUri: '',
      extraAuthParams: ''
    };
  }
  if (provider === 'codex') {
    return {
      id: 'codex',
      label: 'ChatGPT Codex',
      authorizeUrl: CODEX_AUTHORIZE_URL,
      tokenUrl: CODEX_TOKEN_URL,
      clientId: CODEX_CLIENT_ID,
      scopes: CODEX_SCOPES,
      redirectUri: CODEX_REDIRECT_URI,
      extraAuthParams: 'id_token_add_organizations=true&codex_cli_simplified_flow=true' +
        '&originator=codex_cli_rs'
    };
  }
  return {
    id: 'claude',
    label: 'Claude',
    authorizeUrl: CLAUDE_AUTHORIZE_URL,
    tokenUrl: CLAUDE_TOKEN_URL,
    clientId: CLAUDE_CLIENT_ID,
    scopes: CLAUDE_SCOPES,
    redirectUri: CLAUDE_REDIRECT_URI,
    extraAuthParams: ''
  };
}

export function authorizeUrl(
  provider: OAuthProvider,
  challenge: string,
  state: string
): string {
  const config: OAuthProviderConfig = providerConfig(provider);
  if (provider === 'copilot') {
    return '';
  }
  let url: string = config.authorizeUrl +
    '?response_type=code' +
    '&client_id=' + encodeURIComponent(config.clientId) +
    '&redirect_uri=' + encodeURIComponent(config.redirectUri) +
    '&scope=' + encodeURIComponent(config.scopes) +
    '&code_challenge=' + encodeURIComponent(challenge) +
    '&code_challenge_method=S256' +
    '&state=' + encodeURIComponent(state);
  if (config.extraAuthParams.length > 0) {
    url += '&' + config.extraAuthParams;
  }
  return url;
}

function safeDecode(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch (e) {
    return value;
  }
}

/**
 * Accepts what a user can actually copy back from the browser:
 * - the full `http://localhost:.../callback?code=...&state=...` URL,
 * - Anthropic's `code#state` pair,
 * - or a bare authorization code.
 * An `error=` redirect returns null.
 */
export function extractRedirectCode(input: string): RedirectCode | null {
  const text: string = input.trim();
  if (text.length === 0) {
    return null;
  }
  if (text.indexOf('error=') >= 0) {
    return null;
  }
  const queryAt: number = text.indexOf('?');
  if (queryAt >= 0) {
    const query: string = text.substring(queryAt + 1);
    const pieces: string[] = query.split('&');
    let code: string = '';
    let state: string = '';
    for (let i = 0; i < pieces.length; i++) {
      const piece: string = pieces[i];
      const eq: number = piece.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      const key: string = piece.substring(0, eq);
      const value: string = piece.substring(eq + 1);
      if (key === 'code') {
        code = safeDecode(value);
      } else if (key === 'state') {
        state = safeDecode(value);
      }
    }
    return code.length > 0 ? { code: code, state: state } : null;
  }
  const hash: number = text.indexOf('#');
  if (hash > 0) {
    const code: string = text.substring(0, hash).trim();
    const state: string = text.substring(hash + 1).trim();
    return code.length > 0 ? { code: code, state: state } : null;
  }
  return { code: text, state: '' };
}

interface RawTokenResponse {
  access_token?: string;
  refresh_token?: string;
  expires_in?: number;
  id_token?: string;
}

export function tokenFromJson(text: string, now: number): OAuthToken | null {
  let raw: RawTokenResponse;
  try {
    raw = JSON.parse(text) as RawTokenResponse;
  } catch (e) {
    return null;
  }
  if (raw === null || raw === undefined || typeof raw.access_token !== 'string' ||
    raw.access_token.length === 0) {
    return null;
  }
  const expiresIn: number = typeof raw.expires_in === 'number' && raw.expires_in > 0
    ? raw.expires_in
    : 0;
  return {
    accessToken: raw.access_token,
    refreshToken: typeof raw.refresh_token === 'string' ? raw.refresh_token : '',
    expiresAt: expiresIn > 0 ? now + expiresIn * 1000 : OAUTH_UNKNOWN_EXPIRY_MS,
    accountId: '',
    planType: '',
    lastRefresh: now
  };
}

export function tokenJson(token: OAuthToken): string {
  return JSON.stringify(token);
}

export function parseTokenJson(text: string): OAuthToken | null {
  if (text.length === 0) {
    return null;
  }
  let raw: OAuthToken;
  try {
    raw = JSON.parse(text) as OAuthToken;
  } catch (e) {
    return null;
  }
  if (raw === null || raw === undefined || typeof raw.accessToken !== 'string' ||
    raw.accessToken.length === 0) {
    return null;
  }
  return {
    accessToken: raw.accessToken,
    refreshToken: typeof raw.refreshToken === 'string' ? raw.refreshToken : '',
    expiresAt: typeof raw.expiresAt === 'number' && raw.expiresAt > 0 ? raw.expiresAt : 0,
    accountId: typeof raw.accountId === 'string' ? raw.accountId : '',
    planType: typeof raw.planType === 'string' ? raw.planType : '',
    lastRefresh: typeof raw.lastRefresh === 'number' ? raw.lastRefresh : 0
  };
}

export function tokenNeedsRefresh(token: OAuthToken, now: number): boolean {
  if (token.refreshToken.length === 0 || token.expiresAt <= 0) {
    return false;
  }
  return now >= token.expiresAt - OAUTH_REFRESH_BUFFER_MS;
}

/** `abcd******wxyz`: enough to recognise a login without exposing it. */
export function maskToken(token: string): string {
  const length: number = token.length;
  if (length === 0) {
    return '';
  }
  if (length <= 4) {
    let stars: string = '';
    for (let i = 0; i < length; i++) {
      stars += '*';
    }
    return stars;
  }
  const edge: number = Math.min(10, Math.floor(length / 3));
  return token.substring(0, edge) + '**********' + token.substring(length - edge);
}

interface RawJwtClaims {
  chatgpt_account_id?: string;
  chatgpt_plan_type?: string;
  email?: string;
}

/** Codex stores account/plan in the id_token; the payload is not verified. */
export function jwtClaimsFromPayloadJson(text: string): JwtClaims {
  try {
    const raw: RawJwtClaims = JSON.parse(text) as RawJwtClaims;
    return {
      chatgptAccountId: typeof raw.chatgpt_account_id === 'string'
        ? raw.chatgpt_account_id : '',
      chatgptPlanType: typeof raw.chatgpt_plan_type === 'string'
        ? raw.chatgpt_plan_type : '',
      email: typeof raw.email === 'string' ? raw.email : ''
    };
  } catch (e) {
    return { chatgptAccountId: '', chatgptPlanType: '', email: '' };
  }
}

/** JWT payload is base64url; the service decodes it to UTF-8 first. */
export function jwtPayloadSegment(jwt: string): string {
  const parts: string[] = jwt.split('.');
  return parts.length >= 2 ? parts[1] : '';
}

export interface DeviceAuthorization {
  deviceCode: string;
  userCode: string;
  verificationUri: string;
  expiresIn: number;
  interval: number;
}

interface RawDeviceAuthorization {
  device_code?: string;
  user_code?: string;
  verification_uri?: string;
  expires_in?: number;
  interval?: number;
}

export function parseDeviceAuthorization(text: string): DeviceAuthorization | null {
  let raw: RawDeviceAuthorization;
  try {
    raw = JSON.parse(text) as RawDeviceAuthorization;
  } catch (e) {
    return null;
  }
  if (raw === null || raw === undefined || typeof raw.device_code !== 'string' ||
    raw.device_code.length === 0) {
    return null;
  }
  return {
    deviceCode: raw.device_code,
    userCode: typeof raw.user_code === 'string' ? raw.user_code : '',
    verificationUri: typeof raw.verification_uri === 'string' ? raw.verification_uri : '',
    expiresIn: typeof raw.expires_in === 'number' && raw.expires_in > 0
      ? raw.expires_in : 900,
    interval: typeof raw.interval === 'number' && raw.interval > 0 ? raw.interval : 5
  };
}

export type DevicePollKind = 'success' | 'pending' | 'slow_down' | 'denied' | 'expired' | 'fatal';

export interface DevicePollResult {
  kind: DevicePollKind;
  accessToken: string;
  message: string;
}

interface RawDevicePoll {
  access_token?: string;
  error?: string;
  error_description?: string;
}

export function classifyDevicePoll(text: string, httpOk: boolean): DevicePollResult {
  let raw: RawDevicePoll;
  try {
    raw = JSON.parse(text) as RawDevicePoll;
  } catch (e) {
    return { kind: 'fatal', accessToken: '', message: t('无法解析设备码响应') };
  }
  if (raw !== null && raw !== undefined && typeof raw.access_token === 'string' &&
    raw.access_token.length > 0) {
    return { kind: 'success', accessToken: raw.access_token, message: '' };
  }
  const code: string = raw !== null && raw !== undefined && typeof raw.error === 'string'
    ? raw.error : (httpOk ? '' : 'unparsed');
  const detail: string = raw !== null && raw !== undefined &&
    typeof raw.error_description === 'string' ? raw.error_description : '';
  if (code === 'authorization_pending') {
    return { kind: 'pending', accessToken: '', message: '' };
  }
  if (code === 'slow_down') {
    return { kind: 'slow_down', accessToken: '', message: '' };
  }
  if (code === 'access_denied') {
    return { kind: 'denied', accessToken: '', message: detail.length > 0 ? detail : t('已拒绝授权') };
  }
  if (code === 'expired_token') {
    return { kind: 'expired', accessToken: '', message: t('设备码已过期，请重新登录') };
  }
  return {
    kind: 'fatal',
    accessToken: '',
    message: detail.length > 0 ? detail : (t('登录失败：') + (code.length > 0 ? code : t('未知错误')))
  };
}

export function bumpedDeviceInterval(interval: number): number {
  return interval + 5;
}

export interface CopilotSession {
  token: string;
  expiresAt: number;
}

/** Copilot keeps the long-lived GitHub token plus a short-lived session. */
export interface CopilotStorage {
  githubToken: string;
  sessionToken: string;
  sessionExpiresAt: number;
}

export function copilotStorageJson(storage: CopilotStorage): string {
  return JSON.stringify(storage);
}

export function parseCopilotStorage(text: string): CopilotStorage | null {
  if (text.length === 0) {
    return null;
  }
  let raw: CopilotStorage;
  try {
    raw = JSON.parse(text) as CopilotStorage;
  } catch (e) {
    return null;
  }
  if (raw === null || raw === undefined || typeof raw.githubToken !== 'string' ||
    raw.githubToken.length === 0) {
    return null;
  }
  return {
    githubToken: raw.githubToken,
    sessionToken: typeof raw.sessionToken === 'string' ? raw.sessionToken : '',
    sessionExpiresAt: typeof raw.sessionExpiresAt === 'number' && raw.sessionExpiresAt > 0
      ? raw.sessionExpiresAt : 0
  };
}

interface RawCopilotSession {
  token?: string;
  expires_at?: number;
}

/** The exchange returns `expires_at` in Unix seconds. */
export function parseCopilotSession(text: string, now: number): CopilotSession | null {
  let raw: RawCopilotSession;
  try {
    raw = JSON.parse(text) as RawCopilotSession;
  } catch (e) {
    return null;
  }
  if (raw === null || raw === undefined || typeof raw.token !== 'string' ||
    raw.token.length === 0) {
    return null;
  }
  const expiresAt: number = typeof raw.expires_at === 'number' && raw.expires_at > 0
    ? raw.expires_at * 1000
    : now + 25 * 60 * 1000;
  return { token: raw.token, expiresAt: expiresAt };
}
