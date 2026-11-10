import { t } from './I18n';

/** Result of one quick model connectivity check from the model picker. */
export interface ModelTestOutcome {
  ok: boolean;
  text: string;
  message: string;
  elapsedMs: number;
}

/** One compact line shown under the tested model row. */
export function modelTestLine(outcome: ModelTestOutcome): string {
  if (!outcome.ok) {
    return outcome.message.length > 0 ? outcome.message : t('模型测试失败');
  }
  const reply: string = outcome.text.trim();
  if (reply.length === 0) {
    return outcome.message.length > 0 ? outcome.message : t('模型没有返回内容');
  }
  const flat: string = reply.split('\n').join(' ').split('\r').join(' ')
    .split('\t').join(' ').trim();
  const clipped: string = flat.length > 80 ? flat.substring(0, 80) + '…' : flat;
  return outcome.elapsedMs.toString() + ' ms · ' + clipped;
}
