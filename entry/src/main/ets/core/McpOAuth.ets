/**
 * MCP static OAuth (RFC 7636 PKCE + RFC 8707 resource indicator).
 *
 * Mirrors OpenMinis's `MCPOAuthConfig` + `McpPkce`: the user supplies the
 * client id and the authorization/token endpoints, the app runs a PKCE
 * authorization-code flow in the system browser and pastes the callback back
 * (HarmonyOS has no loopback listener for the app). Everything secret — the
 * client secret and the issued tokens — is kept out of settings and lives in
 * the Asset Store instead.
 *
 * Everything here is pure so the parameter construction can be unit-tested.
 */

export const MCP_OAUTH_MODE_STATIC: string = 'static';
/** Distinct from Claude's 54545 so two pending logins never collide. */
export const MCP_OAUTH_LOOPBACK_PORT: number = 54546;
export const MCP_OAUTH_DEFAULT_REDIRECT: string = 'http://localhost:54546/callback';

export interface McpOAuthConfig {
  /** Only `static` is implemented; dynamic client registration is reserved. */
  mode: string;
  clientId: string;
  authorizationEndpoint: string;
  tokenEndpoint: string;
  /** Space-separated scopes, e.g. `openid email`. */
  scopes: string;
  /** Empty means `MCP_OAUTH_DEFAULT_REDIRECT`. */
  redirectUri: string;
  /** Optional RFC 8707 override; empty means the server URL's canonical form. */
  resource: string;
  /**
   * True when a client secret is stored in the Asset Store. The secret itself
   * is never part of settings, backups or exports.
   */
  clientSecretSet: boolean;
}

export interface McpOAuthLoginStart {
  url: string;
  verifier: string;
  state: string;
}

export interface McpOAuthOutcome {
  ok: boolean;
  message: string;
}

export function emptyMcpOAuth(): McpOAuthConfig {
  return {
    mode: MCP_OAUTH_MODE_STATIC,
    clientId: '',
    authorizationEndpoint: '',
    tokenEndpoint: '',
    scopes: '',
    redirectUri: '',
    resource: '',
    clientSecretSet: false
  };
}

/** Trim, default `mode`, and collapse an entirely blank block to empty. */
export function normalizeMcpOAuth(raw: McpOAuthConfig | undefined): McpOAuthConfig {
  if (raw === undefined || raw === null) {
    return emptyMcpOAuth();
  }
  const out: McpOAuthConfig = {
    mode: MCP_OAUTH_MODE_STATIC,
    clientId: typeof raw.clientId === 'string' ? raw.clientId.trim() : '',
    authorizationEndpoint: typeof raw.authorizationEndpoint === 'string'
      ? raw.authorizationEndpoint.trim() : '',
    tokenEndpoint: typeof raw.tokenEndpoint === 'string' ? raw.tokenEndpoint.trim() : '',
    scopes: typeof raw.scopes === 'string' ? raw.scopes.trim() : '',
    redirectUri: typeof raw.redirectUri === 'string' ? raw.redirectUri.trim() : '',
    resource: typeof raw.resource === 'string' ? raw.resource.trim() : '',
    clientSecretSet: raw.clientSecretSet === true
  };
  if (out.clientId.length === 0 && out.authorizationEndpoint.length === 0 &&
    out.tokenEndpoint.length === 0 && out.scopes.length === 0 &&
    out.redirectUri.length === 0 && out.resource.length === 0 &&
    !out.clientSecretSet) {
    return emptyMcpOAuth();
  }
  return out;
}

/** Client id and both endpoints are required before a login can start. */
export function isMcpOAuthConfigured(config: McpOAuthConfig): boolean {
  return config.clientId.length > 0 &&
    config.authorizationEndpoint.length > 0 &&
    config.tokenEndpoint.length > 0;
}

export function effectiveRedirectUri(config: McpOAuthConfig): string {
  return config.redirectUri.length > 0 ? config.redirectUri : MCP_OAUTH_DEFAULT_REDIRECT;
}

/**
 * Canonical MCP resource URI (RFC 8707 §2): trim, drop any fragment, strip
 * trailing slashes; must have a scheme and a host. Returns '' when the input
 * is not a usable absolute URI.
 */
export function canonicalResourceUri(raw: string): string {
  let text: string = raw.trim();
  if (text.length === 0) {
    return '';
  }
  const hash: number = text.indexOf('#');
  if (hash >= 0) {
    text = text.substring(0, hash);
  }
  while (text.length > 0 && text.charAt(text.length - 1) === '/') {
    text = text.substring(0, text.length - 1);
  }
  if (text.length === 0) {
    return '';
  }
  const schemeAt: number = text.indexOf('://');
  if (schemeAt <= 0) {
    return '';
  }
  const scheme: string = text.substring(0, schemeAt);
  const first: number = scheme.charCodeAt(0);
  const firstLetter: boolean =
    (first >= 65 && first <= 90) || (first >= 97 && first <= 122);
  if (!firstLetter) {
    return '';
  }
  for (let i = 1; i < scheme.length; i++) {
    const code: number = scheme.charCodeAt(i);
    const alpha: boolean =
      (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
    const digit: boolean = code >= 48 && code <= 57;
    if (!alpha && !digit && code !== 43 && code !== 45 && code !== 46) {
      return '';
    }
  }
  const rest: string = text.substring(schemeAt + 3);
  let hostEnd: number = rest.length;
  for (let i = 0; i < rest.length; i++) {
    const ch: string = rest.charAt(i);
    if (ch === '/' || ch === '?' || ch === '#') {
      hostEnd = i;
      break;
    }
  }
  const host: string = rest.substring(0, hostEnd);
  if (host.length === 0) {
    return '';
  }
  for (let i = 0; i < host.length; i++) {
    const code: number = host.charCodeAt(i);
    if (code <= 32) {
      return '';
    }
  }
  return text;
}

/** Configured resource when present, otherwise the server URL canonicalized. */
export function effectiveResource(config: McpOAuthConfig, serverUrl: string): string {
  if (config.resource.length > 0) {
    const configured: string = canonicalResourceUri(config.resource);
    return configured.length > 0 ? configured : config.resource.trim();
  }
  return canonicalResourceUri(serverUrl);
}

function enc(value: string): string {
  return encodeURIComponent(value);
}

/**
 * Full authorization-endpoint URL. Query items already on the endpoint are
 * preserved; `resource`/`scope` are omitted when blank. `access_type=offline`
 * and `prompt=consent` are the refresh-token hints OpenMinis sends.
 */
export function buildMcpAuthorizeUrl(
  authorizationEndpoint: string,
  clientId: string,
  redirectUri: string,
  challenge: string,
  state: string,
  resource: string,
  scopes: string
): string {
  let query: string = 'response_type=code' +
    '&client_id=' + enc(clientId) +
    '&redirect_uri=' + enc(redirectUri) +
    '&state=' + enc(state) +
    '&code_challenge=' + enc(challenge) +
    '&code_challenge_method=S256' +
    '&access_type=offline' +
    '&prompt=consent';
  if (resource.length > 0) {
    query += '&resource=' + enc(resource);
  }
  if (scopes.length > 0) {
    query += '&scope=' + enc(scopes);
  }
  const separator: string = authorizationEndpoint.indexOf('?') >= 0 ? '&' : '?';
  return authorizationEndpoint + separator + query;
}

/** Form body for the authorization-code exchange; optionals only when set. */
export function mcpTokenExchangeBody(
  code: string,
  redirectUri: string,
  clientId: string,
  verifier: string,
  clientSecret: string,
  resource: string
): string {
  let body: string = 'grant_type=authorization_code' +
    '&code=' + enc(code) +
    '&redirect_uri=' + enc(redirectUri) +
    '&client_id=' + enc(clientId) +
    '&code_verifier=' + enc(verifier);
  if (clientSecret.length > 0) {
    body += '&client_secret=' + enc(clientSecret);
  }
  if (resource.length > 0) {
    body += '&resource=' + enc(resource);
  }
  return body;
}

/** Form body for a refresh; the refresh token itself is rotated by some servers. */
export function mcpRefreshBody(
  refreshToken: string,
  clientId: string,
  clientSecret: string,
  resource: string
): string {
  let body: string = 'grant_type=refresh_token' +
    '&refresh_token=' + enc(refreshToken) +
    '&client_id=' + enc(clientId);
  if (clientSecret.length > 0) {
    body += '&client_secret=' + enc(clientSecret);
  }
  if (resource.length > 0) {
    body += '&resource=' + enc(resource);
  }
  return body;
}
