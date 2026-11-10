import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import {
  UsageRecord,
  dayKey,
  parseUsage,
  recordUsage
} from '../core/UsageStats';

const STORE_NAME: string = 'minis_usage_store';
const KEY_RECORDS: string = 'records';

/**
 * Local usage rollups. Nothing here leaves the device and no prompt text is
 * stored; a row is just day + model + token counts + request count.
 */
export class UsageStore {
  private static store(context: common.Context): preferences.Preferences {
    const options: preferences.Options = { name: STORE_NAME };
    return preferences.getPreferencesSync(context, options);
  }

  static load(context: common.Context): UsageRecord[] {
    try {
      const raw: preferences.ValueType =
        UsageStore.store(context).getSync(KEY_RECORDS, '');
      return parseUsage(typeof raw === 'string' ? raw as string : '');
    } catch (e) {
      return [];
    }
  }

  /** Merge one settled request; failures are silent (statistics only). */
  static record(
    context: common.Context,
    modelId: string,
    preset: string,
    promptTokens: number,
    completionTokens: number
  ): void {
    if (promptTokens <= 0 && completionTokens <= 0) {
      return;
    }
    try {
      const next: UsageRecord[] = recordUsage(
        UsageStore.load(context), dayKey(Date.now()), modelId, preset,
        promptTokens, completionTokens);
      const store: preferences.Preferences = UsageStore.store(context);
      store.putSync(KEY_RECORDS, JSON.stringify(next));
      store.flush().catch((error: Error) => {
      });
    } catch (e) {
    }
  }

  static clear(context: common.Context): void {
    try {
      const store: preferences.Preferences = UsageStore.store(context);
      store.putSync(KEY_RECORDS, '');
      store.flush().catch((error: Error) => {
      });
    } catch (e) {
    }
  }
}
