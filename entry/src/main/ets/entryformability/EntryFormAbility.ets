import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { WidgetSnapshot } from '../core/WidgetData';
import { WidgetBridge } from '../service/WidgetBridge';
import { I18nService } from '../service/I18n';

/**
 * Background entry point for the home-screen card. The card only shows data
 * the main app published (last conversation title/excerpt and whether a reply
 * is running), so this ability never opens a network connection.
 */
export default class EntryFormAbility extends FormExtensionAbility {
  private formIdOf(want: Want): string {
    const parameters: Record<string, Object> | undefined = want.parameters;
    if (parameters === undefined) {
      return '';
    }
    const raw: Object | undefined = parameters[formInfo.FormParam.IDENTITY_KEY];
    return typeof raw === 'string' ? raw as string : '';
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    try {
      // The card extension runs in its own process, so the catalog has to be
      // loaded here too; a failure only costs the fallback text.
      I18nService.init(this.context);
    } catch (e) {
      // Keep going: the snapshot below is still worth showing.
    }
    const formId: string = this.formIdOf(want);
    WidgetBridge.registerForm(this.context, formId);
    const snapshot: WidgetSnapshot = WidgetBridge.loadSync(this.context);
    return WidgetBridge.binding(snapshot);
  }

  onUpdateForm(formId: string): void {
    const snapshot: WidgetSnapshot = WidgetBridge.loadSync(this.context);
    formProvider.updateForm(formId, WidgetBridge.binding(snapshot))
      .catch((error: Error) => {});
  }

  onRemoveForm(formId: string): void {
    WidgetBridge.unregisterForm(this.context, formId);
  }
}
