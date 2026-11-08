/**
 * SKILL.md documents: optional YAML-ish frontmatter with `name` and
 * `description`, followed by the instruction body. Only the short description
 * is injected into every request; the model calls `read_skill` when it needs
 * the full text, which keeps large skill libraries out of the context budget.
 */
export interface SkillDoc {
  id: string;
  name: string;
  description: string;
  body: string;
}

export function skillIdFromFile(fileName: string): string {
  let base: string = fileName.trim();
  const slash: number = Math.max(base.lastIndexOf('/'), base.lastIndexOf('\\'));
  if (slash >= 0) {
    base = base.substring(slash + 1);
  }
  if (base.toLowerCase().endsWith('.md')) {
    base = base.substring(0, base.length - 3);
  }
  let id: string = '';
  for (let i = 0; i < base.length; i++) {
    const ch: string = base.charAt(i).toLowerCase();
    const code: number = ch.charCodeAt(0);
    if ((code >= 97 && code <= 122) || (code >= 48 && code <= 57) ||
      ch === '-' || ch === '_') {
      id += ch;
    } else if (ch === ' ' || ch === '.') {
      id += '-';
    }
  }
  if (id.length === 0) {
    return 'skill';
  }
  return id.length > 48 ? id.substring(0, 48) : id;
}

function stripQuotes(value: string): string {
  const trimmed: string = value.trim();
  if (trimmed.length >= 2) {
    const first: string = trimmed.charAt(0);
    const last: string = trimmed.charAt(trimmed.length - 1);
    if ((first === '"' && last === '"') || (first === '\'' && last === '\'')) {
      return trimmed.substring(1, trimmed.length - 1);
    }
  }
  return trimmed;
}

export function parseSkillDoc(text: string, fallbackId: string): SkillDoc {
  const lines: string[] = text.split('\n');
  let name: string = '';
  let description: string = '';
  let bodyStart: number = 0;
  if (lines.length > 1 && lines[0].trim() === '---') {
    let close: number = -1;
    for (let i = 1; i < lines.length; i++) {
      if (lines[i].trim() === '---') {
        close = i;
        break;
      }
    }
    if (close > 0) {
      bodyStart = close + 1;
      for (let i = 1; i < close; i++) {
        const line: string = lines[i];
        const colon: number = line.indexOf(':');
        if (colon <= 0) {
          continue;
        }
        const key: string = line.substring(0, colon).trim().toLowerCase();
        const value: string = stripQuotes(line.substring(colon + 1));
        if (key === 'name') {
          name = value;
        } else if (key === 'description') {
          description = value;
        }
      }
    }
  }
  const body: string = lines.slice(bodyStart).join('\n').trim();
  if (name.length === 0) {
    name = fallbackId;
  }
  if (description.length === 0) {
    description = body.length > 120 ? body.substring(0, 120) + '…' : body;
  }
  return {
    id: fallbackId,
    name: name,
    description: description,
    body: body
  };
}

/** Short catalogue inserted in the system prompt; empty when no skill is on. */
export function skillCatalogue(docs: SkillDoc[]): string {
  if (docs.length === 0) {
    return '';
  }
  let text: string = '以下技能（Skills）已启用。需要完整步骤时调用 read_skill 并传入 id：\n';
  for (let i = 0; i < docs.length; i++) {
    text += '- ' + docs[i].name + '（id: ' + docs[i].id + '）：' +
      docs[i].description + '\n';
  }
  return text.trim();
}

export function findSkill(docs: SkillDoc[], idOrName: string): SkillDoc | null {
  const needle: string = idOrName.trim().toLowerCase();
  if (needle.length === 0) {
    return null;
  }
  for (let i = 0; i < docs.length; i++) {
    if (docs[i].id.toLowerCase() === needle || docs[i].name.toLowerCase() === needle) {
      return docs[i];
    }
  }
  return null;
}
