import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import {
  WidgetSnapshot,
  defaultWidgetSnapshot,
  parseWidgetSnapshot,
  widgetSnapshotJson
} from '../core/WidgetData';
import { t } from '../core/I18n';

const STORE_NAME: string = 'minis_widget_store_v1';
const KEY_STATE: string = 'snapshot';
const KEY_FORMS: string = 'form_ids';

/**
 * Glue between the chat screen and the home-screen card.
 *
 * The main app writes a tiny snapshot into preferences; the form extension
 * registers the card ids it hosts in the same store and serves the snapshot
 * on add/update. `publish` also pushes an immediate refresh to every known
 * card, so the card follows the conversation without waiting for the periodic
 * platform update.
 */
export class WidgetBridge {
  private static lastSignature: string = '';

  private static store(context: common.Context): preferences.Preferences {
    const options: preferences.Options = { name: STORE_NAME };
    return preferences.getPreferencesSync(context, options);
  }

  static loadSync(context: common.Context): WidgetSnapshot {
    try {
      const store: preferences.Preferences = WidgetBridge.store(context);
      const raw: preferences.ValueType = store.getSync(KEY_STATE, '');
      if (typeof raw !== 'string') {
        return defaultWidgetSnapshot();
      }
      const parsed: WidgetSnapshot | null = parseWidgetSnapshot(raw as string);
      return parsed !== null ? parsed : defaultWidgetSnapshot();
    } catch (e) {
      return defaultWidgetSnapshot();
    }
  }

  private static formIds(context: common.Context): string[] {
    const out: string[] = [];
    try {
      const store: preferences.Preferences = WidgetBridge.store(context);
      const raw: preferences.ValueType = store.getSync(KEY_FORMS, '');
      if (typeof raw !== 'string' || (raw as string).length === 0) {
        return out;
      }
      const parsed: Object = JSON.parse(raw as string) as Object;
      if (!Array.isArray(parsed)) {
        return out;
      }
      const items: Object[] = parsed as Object[];
      for (let i = 0; i < items.length; i++) {
        if (typeof items[i] === 'string' && (items[i] as string).length > 0) {
          out.push(items[i] as string);
        }
      }
    } catch (e) {
      return out;
    }
    return out;
  }

  private static writeFormIds(context: common.Context, ids: string[]): void {
    try {
      const store: preferences.Preferences = WidgetBridge.store(context);
      store.putSync(KEY_FORMS, JSON.stringify(ids));
      store.flush().catch((error: Error) => {});
    } catch (e) {
      // A failed registry only costs the immediate refresh.
    }
  }

  static registerForm(context: common.Context, formId: string): void {
    if (formId.length === 0) {
      return;
    }
    const ids: string[] = WidgetBridge.formIds(context);
    if (ids.indexOf(formId) >= 0) {
      return;
    }
    ids.push(formId);
    WidgetBridge.writeFormIds(context, ids);
  }

  static unregisterForm(context: common.Context, formId: string): void {
    const ids: string[] = WidgetBridge.formIds(context);
    const next: string[] = [];
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] !== formId) {
        next.push(ids[i]);
      }
    }
    WidgetBridge.writeFormIds(context, next);
  }

  static binding(snapshot: WidgetSnapshot): formBindingData.FormBindingData {
    return formBindingData.createFormBindingData({
      title: snapshot.title,
      body: snapshot.body,
      hint: snapshot.hint
    });
  }

  /** Immediate refresh of every card registered by the extension. */
  static async refreshForms(context: common.Context, snapshot: WidgetSnapshot): Promise<void> {
    const ids: string[] = WidgetBridge.formIds(context);
    if (ids.length === 0) {
      return;
    }
    const data: formBindingData.FormBindingData = WidgetBridge.binding(snapshot);
    for (let i = 0; i < ids.length; i++) {
      try {
        await formProvider.updateForm(ids[i], data);
      } catch (e) {
        // The card may have been removed between the read and the update.
      }
    }
  }

  /** Publish the current conversation; identical snapshots are a no-op. */
  static async publish(
    context: common.Context,
    title: string,
    body: string,
    hint: string
  ): Promise<void> {
    const trimmedTitle: string = title.trim();
    const trimmedBody: string = body.trim();
    const trimmedHint: string = hint.trim();
    const signature: string = trimmedTitle + '|' + trimmedBody + '|' + trimmedHint;
    if (signature === WidgetBridge.lastSignature) {
      return;
    }
    WidgetBridge.lastSignature = signature;
    const snapshot: WidgetSnapshot = {
      title: trimmedTitle.length > 0 ? trimmedTitle : 'Minis',
      body: trimmedBody.length > 0 ? trimmedBody : t('打开应用开始新对话'),
      hint: trimmedHint,
      updatedAt: Date.now()
    };
    try {
      const store: preferences.Preferences = WidgetBridge.store(context);
      store.putSync(KEY_STATE, widgetSnapshotJson(snapshot));
      await store.flush();
    } catch (e) {
      return;
    }
    await WidgetBridge.refreshForms(context, snapshot);
  }
}
