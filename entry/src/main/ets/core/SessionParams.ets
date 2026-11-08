import { AppSettings, SessionMeta, ThinkingLevel } from './Types';
import { cloneSettings } from './Types';
import { t } from './I18n';

/**
 * Per-session overrides. OpenMinis lets a conversation pick its own model,
 * thinking level and extra instructions; here they live on `SessionMeta` and
 * an empty string means "inherit the global setting".
 */
export function isThinkingOverride(value: string): boolean {
  return value === 'off' || value === 'low' || value === 'medium' || value === 'high';
}

export function applySessionParams(
  meta: SessionMeta,
  model: string,
  thinking: string,
  prompt: string
): void {
  meta.modelOverride = model.trim();
  meta.thinkingOverride = isThinkingOverride(thinking) ? thinking : '';
  meta.promptOverride = prompt.trim();
}

/** Kept separate from `applySessionParams` so callers can clear everything. */
export function clearSessionParams(meta: SessionMeta): void {
  meta.modelOverride = '';
  meta.thinkingOverride = '';
  meta.promptOverride = '';
}

export function hasSessionOverride(meta: SessionMeta | null): boolean {
  if (meta === null) {
    return false;
  }
  return (meta.modelOverride !== undefined && meta.modelOverride.length > 0) ||
    (meta.thinkingOverride !== undefined && meta.thinkingOverride.length > 0) ||
    (meta.promptOverride !== undefined && meta.promptOverride.length > 0);
}

/**
 * Copy the global settings and apply the session's overrides. The returned
 * object is always safe to hand to `AgentRuntime`, which never mutates it.
 */
export function effectiveSettings(base: AppSettings, meta: SessionMeta | null): AppSettings {
  const next: AppSettings = cloneSettings(base);
  if (meta === null) {
    return next;
  }
  const model: string = meta.modelOverride !== undefined ? meta.modelOverride.trim() : '';
  if (model.length > 0) {
    next.modelId = model;
  }
  const thinking: string = meta.thinkingOverride !== undefined ? meta.thinkingOverride : '';
  if (isThinkingOverride(thinking)) {
    next.thinkingLevel = thinking as ThinkingLevel;
  }
  const prompt: string = meta.promptOverride !== undefined ? meta.promptOverride.trim() : '';
  if (prompt.length > 0) {
    const basePrompt: string = next.systemPrompt.trim();
    next.systemPrompt = basePrompt.length > 0 ? basePrompt + '\n\n' + prompt : prompt;
  }
  return next;
}

/** One-line label for the session action sheet; empty when inheriting all. */
export function sessionParamSummary(meta: SessionMeta | null): string {
  if (meta === null) {
    return '';
  }
  const parts: string[] = [];
  if (meta.modelOverride !== undefined && meta.modelOverride.length > 0) {
    parts.push(meta.modelOverride);
  }
  if (meta.thinkingOverride !== undefined && isThinkingOverride(meta.thinkingOverride)) {
    parts.push(t('思考 ') + meta.thinkingOverride);
  }
  if (meta.promptOverride !== undefined && meta.promptOverride.length > 0) {
    parts.push(t('追加指令'));
  }
  return parts.join(t(' · '));
}
