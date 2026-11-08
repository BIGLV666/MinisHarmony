/**
 * Named subagent roster, following OpenMinis `SubAgentDefinition`.
 *
 * One built-in agent (`helper`) exists everywhere. The user may add up to ten
 * named agents; each has a canonical wire name (the value the model emits in
 * `subagent_task.agent`), a short description the main model reads to choose,
 * and optional instructions appended to the child's system prompt.
 *
 * The roster is injected into the main conversation's system prompt on every
 * turn, so the size limits are a fixed per-request cost, not paranoia:
 * 10 × (40 + 200) characters is roughly 800 tokens.
 */

export interface SubAgentDefinition {
  id: string;
  /** Canonical identifier: `[a-z0-9_-]`, at most 40 characters. */
  name: string;
  /** The only free text that reaches the main conversation. */
  description: string;
  /** Child-session only; never injected into the parent. */
  instructions: string;
  builtIn: boolean;
}

/** Including the built-in one. */
export const MAX_SUB_AGENTS: number = 10;
export const SUB_AGENT_NAME_MAX: number = 40;
export const SUB_AGENT_DESCRIPTION_MAX: number = 200;
export const SUB_AGENT_INSTRUCTIONS_MAX: number = 4000;
export const BUILTIN_AGENT_ID: string = 'builtin-helper';
export const BUILTIN_AGENT_NAME: string = 'helper';
const BUILTIN_DESCRIPTION: string =
  '通用子代理：独立上下文和工具循环，适合调研、批量修改等多步任务。';
const GENERIC_BRIEF: string =
  '你是一个独立的子代理。专注完成用户交代的任务，' +
  '完成后用简洁的最终结论回答；不要询问用户，也不要等待确认。';

/** The one definition every installation has. */
export function builtinAgent(): SubAgentDefinition {
  return {
    id: BUILTIN_AGENT_ID,
    name: BUILTIN_AGENT_NAME,
    description: BUILTIN_DESCRIPTION,
    instructions: '',
    builtIn: true
  };
}

export function defaultAgents(): SubAgentDefinition[] {
  return [builtinAgent()];
}

/** Lowercase and replace everything outside `[a-z0-9_-]` with `-`. */
export function normalizeAgentName(raw: string): string {
  const lower: string = raw.trim().toLowerCase();
  let out: string = '';
  for (let i = 0; i < lower.length && out.length < SUB_AGENT_NAME_MAX; i++) {
    const ch: string = lower.charAt(i);
    const code: number = lower.charCodeAt(i);
    const letter: boolean = code >= 97 && code <= 122;
    const digit: boolean = code >= 48 && code <= 57;
    if (letter || digit || ch === '_' || ch === '-') {
      out += ch;
    } else {
      out += '-';
    }
  }
  out = out.replace(/-+/g, '-');
  out = out.replace(/^-+/, '').replace(/-+$/, '');
  return out;
}

function clip(value: string, max: number): string {
  return value.length > max ? value.substring(0, max) : value;
}

function normalizeOne(raw: SubAgentDefinition, index: number): SubAgentDefinition {
  const name: string = normalizeAgentName(raw.name !== undefined ? raw.name : '');
  const description: string = clip(raw.description !== undefined
    ? raw.description.trim() : '', SUB_AGENT_DESCRIPTION_MAX);
  const instructions: string = clip(raw.instructions !== undefined
    ? raw.instructions.trim() : '', SUB_AGENT_INSTRUCTIONS_MAX);
  return {
    id: raw.id !== undefined && raw.id.length > 0
      ? raw.id
      : 'agent-' + index.toString(),
    name: name.length > 0 ? name : 'agent',
    description: description,
    instructions: instructions,
    builtIn: false
  };
}

/**
 * Defensive normalization for stored, imported or hand-edited rosters: the
 * built-in agent is always first, names are canonical and unique, and the
 * count never exceeds the limit. Order is otherwise preserved.
 */
export function normalizeAgents(raw: SubAgentDefinition[] | undefined): SubAgentDefinition[] {
  const out: SubAgentDefinition[] = [builtinAgent()];
  if (raw === undefined || !Array.isArray(raw)) {
    return out;
  }
  const seen: string[] = [BUILTIN_AGENT_NAME];
  for (let i = 0; i < raw.length; i++) {
    if (out.length >= MAX_SUB_AGENTS) {
      break;
    }
    const item: SubAgentDefinition | null = raw[i];
    if (item === null || item === undefined || item.builtIn === true) {
      continue;
    }
    const agent: SubAgentDefinition = normalizeOne(item, out.length);
    if (seen.indexOf(agent.name) >= 0) {
      continue;
    }
    seen.push(agent.name);
    out.push(agent);
  }
  return out;
}

/** Roster lines for the main system prompt; empty when only `helper` exists. */
export function rosterPrompt(agents: SubAgentDefinition[]): string {
  const list: SubAgentDefinition[] = normalizeAgents(agents);
  if (list.length <= 1) {
    return '';
  }
  const lines: string[] = ['## 子代理名册',
    'subagent_task 的 agent 参数可选：'];
  for (let i = 0; i < list.length; i++) {
    lines.push('- ' + list[i].name + '：' + list[i].description);
  }
  lines.push('不写 agent 时使用 ' + BUILTIN_AGENT_NAME + '。');
  return lines.join('\n');
}

/** Exact name match; empty means the built-in agent; unknown returns null. */
export function resolveAgent(
  agents: SubAgentDefinition[],
  name: string
): SubAgentDefinition | null {
  const wanted: string = normalizeAgentName(name);
  if (wanted.length === 0) {
    return builtinAgent();
  }
  const list: SubAgentDefinition[] = normalizeAgents(agents);
  for (let i = 0; i < list.length; i++) {
    if (list[i].name === wanted) {
      return list[i];
    }
  }
  return null;
}

/** Comma-separated names, for error messages. */
export function agentNameList(agents: SubAgentDefinition[]): string {
  const list: SubAgentDefinition[] = normalizeAgents(agents);
  const names: string[] = [];
  for (let i = 0; i < list.length; i++) {
    names.push(list[i].name);
  }
  return names.join('、');
}

/** The child's system prompt: generic brief plus the agent's own text. */
export function childBrief(agent: SubAgentDefinition): string {
  const extra: string = agent.instructions.trim();
  return extra.length > 0 ? GENERIC_BRIEF + '\n\n' + extra : GENERIC_BRIEF;
}

/** `子代理 · 名字 · 标签`, matching OpenMinis' child session title. */
export function childSessionTitle(label: string, agentName: string): string {
  const name: string = agentName.trim();
  const text: string = label.trim();
  if (text.length === 0) {
    return name.length > 0 && name !== BUILTIN_AGENT_NAME
      ? '子代理 · ' + name
      : '子代理';
  }
  if (name.length === 0 || name === BUILTIN_AGENT_NAME) {
    return '子代理 · ' + text;
  }
  return '子代理 · ' + name + ' · ' + text;
}
