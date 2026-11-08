/**
 * URL helpers shared by the in-app browser and the `browser_use` tool.
 *
 * Only http(s) is accepted: a bare host gets `https://`, which is what users
 * expect when typing in a tablet address bar. Everything else is left to the
 * system browser.
 */

export function normalizeWebUrl(input: string): string {
  let value: string = input.trim();
  if (value.length === 0) {
    return '';
  }
  const lower: string = value.toLowerCase();
  if (lower.indexOf('http://') !== 0 && lower.indexOf('https://') !== 0) {
    value = 'https://' + value;
  }
  return value;
}

/**
 * Host for the browser's title line: `https://www.example.com/a?q=1` becomes
 * `example.com`. Ports and userinfo are dropped so the line stays short.
 */
export function webHost(input: string): string {
  let value: string = input.trim();
  const scheme: number = value.indexOf('://');
  if (scheme >= 0) {
    value = value.substring(scheme + 3);
  }
  const slash: number = value.indexOf('/');
  if (slash >= 0) {
    value = value.substring(0, slash);
  }
  const query: number = value.indexOf('?');
  if (query >= 0) {
    value = value.substring(0, query);
  }
  const hash: number = value.indexOf('#');
  if (hash >= 0) {
    value = value.substring(0, hash);
  }
  const at: number = value.lastIndexOf('@');
  if (at >= 0) {
    value = value.substring(at + 1);
  }
  const colon: number = value.indexOf(':');
  if (colon >= 0) {
    value = value.substring(0, colon);
  }
  if (value.toLowerCase().indexOf('www.') === 0) {
    value = value.substring(4);
  }
  return value;
}
