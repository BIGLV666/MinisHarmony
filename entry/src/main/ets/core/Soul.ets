import { t } from './I18n';
/**
 * Lightweight persona layer. OpenMinis loads a SOUL.md identity document; the
 * tablet build ships a few built-in personas that are prepended to the system
 * prompt. The user's own system prompt and a session's extra instructions still
 * come after, so they can refine or override the persona for one conversation.
 */
export interface SoulPreset {
  id: string;
  name: string;
  prompt: string;
}

export const DEFAULT_SOUL_ID: string = 'general';

export function soulPresets(): SoulPreset[] {
  return [
  {
    id: 'general',
    name: t('通用'),
    prompt: ''
  },
  {
    id: 'engineer',
    name: t('严谨工程师'),
    prompt: t('你是一名严谨的软件工程师。优先给出可运行、可维护的方案；') +
      t('指出边界条件与风险，不臆造 API 或事实。')
  },
  {
    id: 'concise',
    name: t('简洁'),
    prompt: t('回答尽量简洁：先给结论，再补充必要细节；避免客套与重复。')
  },
  {
    id: 'teacher',
    name: t('耐心讲解'),
    prompt: t('你是一名耐心的老师。用循序渐进的方式解释概念，必要时给出例子，') +
      t('并先确认读者已有的背景。')
  },
  {
    id: 'creative',
    name: t('创意写作'),
    prompt: t('你是一名有创意的写作助手。语言生动、结构清晰，敢于尝试不同的表达，') +
      t('同时尊重用户给出的设定与事实。')
  }
  ];
}

export function normalizeSoulId(value: string | undefined): string {
  if (value === undefined || value.length === 0) {
    return DEFAULT_SOUL_ID;
  }
  for (let i = 0; i < soulPresets().length; i++) {
    if (soulPresets()[i].id === value) {
      return value;
    }
  }
  return DEFAULT_SOUL_ID;
}

export function soulPrompt(id: string): string {
  const normalized: string = normalizeSoulId(id);
  for (let i = 0; i < soulPresets().length; i++) {
    if (soulPresets()[i].id === normalized) {
      return soulPresets()[i].prompt;
    }
  }
  return '';
}
