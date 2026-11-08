import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { WidgetSnapshot } from '../core/WidgetData';
import { WidgetBridge } from '../service/WidgetBridge';

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
