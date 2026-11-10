/**
 * Per-session MCP server switches. A session only stores the ids it has turned
 * off; anything absent follows the global server settings. Pure array helpers
 * so the Node harness can test normalisation and toggling.
 */

/** Trim, drop empties and duplicates while keeping the first-seen order. */
export function normalizeMcpDisabled(ids: string[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < ids.length; i++) {
    const id: string = ids[i].trim();
    if (id.length > 0 && out.indexOf(id) < 0) {
      out.push(id);
    }
  }
  return out;
}

export function isMcpDisabled(ids: string[], serverId: string): boolean {
  return ids.indexOf(serverId) >= 0;
}

/** Return a new list with one server switched off or back to global. */
export function setMcpDisabled(
  ids: string[],
  serverId: string,
  disabled: boolean
): string[] {
  const id: string = serverId.trim();
  if (id.length === 0) {
    return normalizeMcpDisabled(ids);
  }
  const out: string[] = [];
  for (let i = 0; i < ids.length; i++) {
    if (ids[i] !== id) {
      out.push(ids[i]);
    }
  }
  if (disabled) {
    out.push(id);
  }
  return normalizeMcpDisabled(out);
}

/**
 * The mirror list for globally disabled servers a session turns back on.
 * Kept separate from `mcpDisabled` so toggling one never erases the other.
 */
export function normalizeMcpEnabled(ids: string[]): string[] {
  return normalizeMcpDisabled(ids);
}

export function isMcpEnabled(ids: string[], serverId: string): boolean {
  return ids.indexOf(serverId) >= 0;
}

export function setMcpEnabled(
  ids: string[],
  serverId: string,
  enabled: boolean
): string[] {
  const id: string = serverId.trim();
  if (id.length === 0) {
    return normalizeMcpEnabled(ids);
  }
  const out: string[] = [];
  for (let i = 0; i < ids.length; i++) {
    if (ids[i] !== id) {
      out.push(ids[i]);
    }
  }
  if (enabled) {
    out.push(id);
  }
  return normalizeMcpEnabled(out);
}

/** Effective switch: globally disabled servers need a per-session override. */
export function mcpServerActive(
  globallyEnabled: boolean,
  disabled: string[],
  enabled: string[],
  serverId: string
): boolean {
  return globallyEnabled
    ? !isMcpDisabled(disabled, serverId)
    : isMcpEnabled(enabled, serverId);
}
