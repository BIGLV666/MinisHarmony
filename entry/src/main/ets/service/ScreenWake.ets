import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

/**
 * Keep the tablet awake only while a reply is streaming. Failing silently is
 * deliberate: the window may already be gone when a background run finishes.
 */
export async function keepScreenOn(
  context: common.UIAbilityContext,
  on: boolean
): Promise<void> {
  try {
    const win: window.Window = await window.getLastWindow(context);
    await win.setWindowKeepScreenOn(on);
  } catch (e) {
    // The ability is not attached (or the platform refused); no-op.
  }
}
