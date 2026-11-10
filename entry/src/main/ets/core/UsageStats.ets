/**
 * Token usage aggregation. Every settled assistant turn contributes one
 * request; records are merged per (day, model, preset) so preferences hold a
 * compact history instead of one row per request. Pure functions so the Node
 * harness can exercise parsing, merging and rollups.
 */

export interface UsageRecord {
  /** Local calendar day, `YYYY-MM-DD`. */
  date: string;
  model: string;
  preset: string;
  prompt: number;
  completion: number;
  requests: number;
}

export interface UsageTotals {
  prompt: number;
  completion: number;
  requests: number;
}

export interface UsageModelTotal {
  model: string;
  prompt: number;
  completion: number;
  requests: number;
}

export interface UsageDayTotal {
  date: string;
  prompt: number;
  completion: number;
  requests: number;
}

/** Distinct day/model rows kept; older days fall off first. */
export const USAGE_RECORD_LIMIT: number = 400;

function pad(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

/** Local day key; usage follows the device timezone, like the sidebar. */
export function dayKey(timestamp: number): string {
  const date: Date = new Date(timestamp);
  return date.getFullYear().toString() + '-' + pad(date.getMonth() + 1) + '-' +
    pad(date.getDate());
}

function count(raw: number): number {
  return raw > 0 ? Math.floor(raw) : 0;
}

export function parseUsage(raw: string): UsageRecord[] {
  if (raw.trim().length === 0) {
    return [];
  }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(raw) as Object;
  } catch (e) {
    return [];
  }
  if (!Array.isArray(parsed)) {
    return [];
  }
  const result: UsageRecord[] = [];
  const list: Object[] = parsed as Object[];
  for (let i = 0; i < list.length; i++) {
    const item: Record<string, Object> = list[i] as Record<string, Object>;
    const date: string = typeof item.date === 'string' ? item.date as string : '';
    const model: string = typeof item.model === 'string' ? item.model as string : '';
    if (date.length !== 10 || model.trim().length === 0) {
      continue;
    }
    result.push({
      date: date,
      model: model.trim(),
      preset: typeof item.preset === 'string' ? item.preset as string : '',
      prompt: count(typeof item.prompt === 'number' ? item.prompt as number : 0),
      completion: count(typeof item.completion === 'number'
        ? item.completion as number : 0),
      requests: count(typeof item.requests === 'number' ? item.requests as number : 0)
    });
  }
  return result;
}

function sameRow(item: UsageRecord, date: string, model: string,
  preset: string): boolean {
  return item.date === date && item.model === model && item.preset === preset;
}

/** Merge one request into the rollup and keep only the newest rows. */
export function recordUsage(
  records: UsageRecord[],
  date: string,
  model: string,
  preset: string,
  prompt: number,
  completion: number
): UsageRecord[] {
  if (date.length === 0 || model.trim().length === 0) {
    return records;
  }
  const next: UsageRecord[] = [];
  let merged: boolean = false;
  for (let i = 0; i < records.length; i++) {
    const item: UsageRecord = records[i];
    if (!merged && sameRow(item, date, model.trim(), preset)) {
      next.push({
        date: item.date,
        model: item.model,
        preset: item.preset,
        prompt: item.prompt + count(prompt),
        completion: item.completion + count(completion),
        requests: item.requests + 1
      });
      merged = true;
    } else {
      next.push(item);
    }
  }
  if (!merged) {
    next.push({
      date: date,
      model: model.trim(),
      preset: preset,
      prompt: count(prompt),
      completion: count(completion),
      requests: 1
    });
  }
  if (next.length <= USAGE_RECORD_LIMIT) {
    return next;
  }
  next.sort((a: UsageRecord, b: UsageRecord) => a.date < b.date ? 1 : (a.date > b.date ? -1 : 0));
  const kept: UsageRecord[] = next.slice(0, USAGE_RECORD_LIMIT);
  kept.sort((a: UsageRecord, b: UsageRecord) => a.date < b.date ? -1 : (a.date > b.date ? 1 : 0));
  return kept;
}

export function usageTotal(records: UsageRecord[]): UsageTotals {
  let prompt: number = 0;
  let completion: number = 0;
  let requests: number = 0;
  for (let i = 0; i < records.length; i++) {
    prompt += records[i].prompt;
    completion += records[i].completion;
    requests += records[i].requests;
  }
  return { prompt: prompt, completion: completion, requests: requests };
}

/** Totals per model across all days, largest token count first. */
export function usageByModel(records: UsageRecord[]): UsageModelTotal[] {
  const models: string[] = [];
  const prompt: number[] = [];
  const completion: number[] = [];
  const requests: number[] = [];
  for (let i = 0; i < records.length; i++) {
    const item: UsageRecord = records[i];
    let at: number = models.indexOf(item.model);
    if (at < 0) {
      models.push(item.model);
      prompt.push(0);
      completion.push(0);
      requests.push(0);
      at = models.length - 1;
    }
    prompt[at] += item.prompt;
    completion[at] += item.completion;
    requests[at] += item.requests;
  }
  const result: UsageModelTotal[] = [];
  for (let i = 0; i < models.length; i++) {
    result.push({
      model: models[i],
      prompt: prompt[i],
      completion: completion[i],
      requests: requests[i]
    });
  }
  result.sort((a: UsageModelTotal, b: UsageModelTotal) =>
    (b.prompt + b.completion) - (a.prompt + a.completion));
  return result;
}

/** Totals per day, newest first; `limit` caps the list. */
export function usageByDay(records: UsageRecord[], limit: number): UsageDayTotal[] {
  const days: string[] = [];
  const prompt: number[] = [];
  const completion: number[] = [];
  const requests: number[] = [];
  for (let i = 0; i < records.length; i++) {
    const item: UsageRecord = records[i];
    let at: number = days.indexOf(item.date);
    if (at < 0) {
      days.push(item.date);
      prompt.push(0);
      completion.push(0);
      requests.push(0);
      at = days.length - 1;
    }
    prompt[at] += item.prompt;
    completion[at] += item.completion;
    requests[at] += item.requests;
  }
  const result: UsageDayTotal[] = [];
  for (let i = 0; i < days.length; i++) {
    result.push({
      date: days[i],
      prompt: prompt[i],
      completion: completion[i],
      requests: requests[i]
    });
  }
  result.sort((a: UsageDayTotal, b: UsageDayTotal) =>
    a.date < b.date ? 1 : (a.date > b.date ? -1 : 0));
  return limit > 0 && result.length > limit ? result.slice(0, limit) : result;
}
