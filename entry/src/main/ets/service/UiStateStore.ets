import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'minis_ui_state';
const KEY_LAST_SESSION: string = 'lastSessionId';

/**
 * Small UI-only state that should survive a restart but does not belong in
 * settings (and therefore not in backups or the settings audit).
 */
export class UiStateStore {
  private static store(context: common.Context): preferences.Preferences {
    const options: preferences.Options = { name: STORE_NAME };
    return preferences.getPreferencesSync(context, options);
  }

  static lastSession(context: common.Context): string {
    try {
      const raw: preferences.ValueType =
        UiStateStore.store(context).getSync(KEY_LAST_SESSION, '');
      return typeof raw === 'string' ? raw as string : '';
    } catch (e) {
      return '';
    }
  }

  static rememberSession(context: common.Context, id: string): void {
    if (id.length === 0) {
      return;
    }
    try {
      const store: preferences.Preferences = UiStateStore.store(context);
      store.putSync(KEY_LAST_SESSION, id);
      store.flush().catch((error: Error) => {
      });
    } catch (e) {
    }
  }

  static forgetSession(context: common.Context): void {
    try {
      const store: preferences.Preferences = UiStateStore.store(context);
      store.putSync(KEY_LAST_SESSION, '');
      store.flush().catch((error: Error) => {
      });
    } catch (e) {
    }
  }
}
