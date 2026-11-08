import { t } from './I18n';
/**
 * Exact-string file editing, the HarmonyOS counterpart of OpenMinis
 * `file_edit`. Pure string logic so it runs under the Node test harness;
 * LocalToolRuntime owns the file I/O and the workspace jail.
 */

export interface EditOutcome {
  ok: boolean;
  content: string;
  message: string;
  replacements: number;
}

export function countOccurrences(haystack: string, needle: string): number {
  if (needle.length === 0) {
    return 0;
  }
  let count: number = 0;
  let from: number = 0;
  while (true) {
    const at: number = haystack.indexOf(needle, from);
    if (at < 0) {
      break;
    }
    count++;
    from = at + needle.length;
  }
  return count;
}

/**
 * Replace `oldText` with `newText`.
 *
 * A missing or repeated `oldText` is an error rather than a guess: silently
 * editing the wrong occurrence is worse than asking the model for a longer
 * anchor. `replaceAll` opts into replacing every occurrence.
 */
export function applyExactEdit(
  source: string,
  oldText: string,
  newText: string,
  replaceAll: boolean
): EditOutcome {
  if (oldText.length === 0) {
    return {
      ok: false,
      content: source,
      message: t('old_string 不能为空。请提供要替换的确切文本。'),
      replacements: 0
    };
  }
  if (oldText === newText) {
    return {
      ok: false,
      content: source,
      message: t('old_string 与 new_string 相同，没有需要修改的内容。'),
      replacements: 0
    };
  }
  const count: number = countOccurrences(source, oldText);
  if (count === 0) {
    return {
      ok: false,
      content: source,
      message: t('没有找到 old_string。请先用 read_file 确认原文（注意缩进、空格与换行）。'),
      replacements: 0
    };
  }
  if (count > 1 && !replaceAll) {
    return {
      ok: false,
      content: source,
      message: t('old_string 出现了 ') + count.toString() +
        t(' 次。请提供更多上下文使其唯一，或设置 replace_all=true。'),
      replacements: 0
    };
  }
  if (replaceAll) {
    return {
      ok: true,
      content: source.split(oldText).join(newText),
      message: t('已替换 ') + count.toString() + t(' 处。'),
      replacements: count
    };
  }
  const at: number = source.indexOf(oldText);
  const updated: string =
    source.substring(0, at) + newText + source.substring(at + oldText.length);
  return {
    ok: true,
    content: updated,
    message: t('已替换 1 处。'),
    replacements: 1
  };
}
