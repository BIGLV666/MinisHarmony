/**
 * Detects a model stuck calling the same tool with identical arguments.
 *
 * Only *consecutive* repeats count: alternating between two calls is a normal
 * exploration pattern, while the same call three times in a row almost always
 * means the model is not making progress. The agent loop prepends a warning to
 * the tool result, which the model sees on its next turn.
 *
 * Pure: no HarmonyOS imports, exercised by scripts/test-core.mjs.
 */

export const TOOL_LOOP_THRESHOLD: number = 3;

export class ToolLoopGuard {
  private lastKey: string = '';
  private consecutive: number = 0;

  /** Returns how many times this exact call has repeated in a row. */
  observe(name: string, argumentsText: string): number {
    const key: string = name + '\n' + argumentsText;
    if (key === this.lastKey) {
      this.consecutive++;
    } else {
      this.lastKey = key;
      this.consecutive = 1;
    }
    return this.consecutive;
  }

  reset(): void {
    this.lastKey = '';
    this.consecutive = 0;
  }
}

export function toolLoopWarning(name: string, count: number): string {
  return '注意：检测到重复工具调用：' + name + ' 已用完全相同的参数连续调用 ' +
    count.toString() + ' 次。继续重复不会得到新信息；请改用其他方法，' +
    '或直接基于已有结果回答。';
}
