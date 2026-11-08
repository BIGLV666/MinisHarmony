/**
 * Repair for malformed tool-argument JSON emitted by a model.
 *
 * Models occasionally stream a truncated object, wrap it in a Markdown fence,
 * or leave a trailing comma. Sending that to JSON.parse inside a tool turns a
 * recoverable formatting slip into a failed turn, so the agent loop runs this
 * pre-pass and only falls back to the original text when nothing parses.
 *
 * Pure: no HarmonyOS imports, exercised by scripts/test-core.mjs.
 */

export interface ArgsRepair {
  text: string;
  changed: boolean;
  /** Short tag for diagnostics: fence / truncation / trailing-comma / empty. */
  strategy: string;
}

function parses(text: string): boolean {
  try {
    JSON.parse(text);
    return true;
  } catch (e) {
    return false;
  }
}

function stripFence(raw: string): string {
  const trimmed: string = raw.trim();
  if (!trimmed.startsWith('```')) {
    return trimmed;
  }
  let body: string = trimmed.substring(3);
  if (body.startsWith('json')) {
    body = body.substring(4);
  }
  const end: number = body.lastIndexOf('```');
  if (end >= 0) {
    body = body.substring(0, end);
  }
  return body.trim();
}

const CLOSURES: string[] = [
  '', '"', '"}', '"]}', '}', '}}', ']}', ']}}', ']', ']]'
];

/**
 * Return the best-effort valid JSON object. The original string is returned
 * unchanged when no strategy works, so the tool still reports a clear parse
 * error instead of silently doing something different.
 */
export function repairToolArguments(raw: string): ArgsRepair {
  const original: string = raw;
  const trimmed: string = raw.trim();
  if (trimmed.length === 0) {
    return { text: '{}', changed: original !== '{}', strategy: 'empty' };
  }
  if (parses(trimmed)) {
    const trimmedChanged: boolean = trimmed !== original;
    return {
      text: trimmed,
      changed: trimmedChanged,
      strategy: trimmedChanged ? 'trim' : ''
    };
  }

  const unfenced: string = stripFence(trimmed);
  if (unfenced !== trimmed && parses(unfenced)) {
    return { text: unfenced, changed: true, strategy: 'fence' };
  }

  if (unfenced.startsWith('{')) {
    for (let i = 0; i < CLOSURES.length; i++) {
      const candidate: string = unfenced + CLOSURES[i];
      if (parses(candidate)) {
        return {
          text: candidate,
          changed: true,
          strategy: 'truncation+' + CLOSURES[i]
        };
      }
    }
  }

  const withoutTrailing: string =
    unfenced.replace(new RegExp(',\\s*([}\\]])', 'g'), '$1');
  if (withoutTrailing !== unfenced && parses(withoutTrailing)) {
    return { text: withoutTrailing, changed: true, strategy: 'trailing-comma' };
  }

  return { text: original, changed: false, strategy: '' };
}
