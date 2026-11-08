import { common, Want, WantAgent, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';

/**
 * Keeps the process alive while a reply is generating so the SSE connection is
 * not suspended when the user switches apps. A continuous task shows a system
 * notification; it is started only for the duration of one agent run.
 *
 * Everything here is best-effort: a denied permission or an unsupported device
 * must never break the chat. The run simply continues in the foreground.
 */
export class BackgroundGuard {
  private static active: boolean = false;
  private static wanted: boolean = false;
  private static context: common.UIAbilityContext | null = null;
  private static token: number = 0;

  static async begin(context: common.UIAbilityContext): Promise<void> {
    BackgroundGuard.context = context;
    BackgroundGuard.wanted = true;
    const token: number = BackgroundGuard.token;
    if (BackgroundGuard.active) {
      return;
    }
    try {
      const want: Want = {
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name
      };
      const info: wantAgent.WantAgentInfo = {
        wants: [want],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0
      };
      const agent: WantAgent = await wantAgent.getWantAgent(info);
      await backgroundTaskManager.startBackgroundRunning(
        context,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
        agent
      );
      BackgroundGuard.active = true;
      // The run may have finished while the request was in flight.
      if (!BackgroundGuard.wanted || token !== BackgroundGuard.token) {
        await BackgroundGuard.end();
      }
    } catch (e) {
      BackgroundGuard.active = false;
    }
  }

  static async end(): Promise<void> {
    BackgroundGuard.wanted = false;
    BackgroundGuard.token++;
    const context: common.UIAbilityContext | null = BackgroundGuard.context;
    if (!BackgroundGuard.active || context === null) {
      return;
    }
    BackgroundGuard.active = false;
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
    } catch (e) {
      // Already stopped by the system; nothing else to clean up.
    }
  }

  static isActive(): boolean {
    return BackgroundGuard.active;
  }
}
