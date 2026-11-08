import { notificationManager } from '@kit.NotificationKit';
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { t } from '../core/I18n';

/**
 * Generation reminders in the notification centre. They are only published
 * while the app is in the background, so a foreground user never sees a
 * duplicate banner. All calls fail silently: a device that has notifications
 * turned off must not disturb the agent loop.
 */
const GENERATION_NOTIFICATION_ID: number = 1010;

async function buildAgent(context: common.UIAbilityContext): Promise<WantAgent | null> {
  try {
    const info: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    return await wantAgent.getWantAgent(info);
  } catch (e) {
    return null;
  }
}

async function publish(context: common.UIAbilityContext, text: string, ongoing: boolean): Promise<void> {
  try {
    const enabled: boolean = await notificationManager.isNotificationEnabled();
    if (!enabled) {
      return;
    }
    const agent: WantAgent | null = await buildAgent(context);
    const request: notificationManager.NotificationRequest = {
      id: GENERATION_NOTIFICATION_ID,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: 'Minis Harmony',
          text: text
        }
      },
      isOngoing: ongoing,
      tapDismissed: true
    };
    if (agent !== null) {
      request.wantAgent = agent;
    }
    await notificationManager.publish(request);
  } catch (e) {
    // Notification unavailable or rejected; the chat itself is unaffected.
  }
}

/** Called when the app leaves the foreground while a turn is still running. */
export async function publishGenerating(context: common.UIAbilityContext, title: string): Promise<void> {
  const label: string = title.length > 0 ? title : t('当前对话');
  await publish(context, label + t(' · 正在生成回复…'), true);
}

/** Replaces the ongoing notification with a completed reminder. */
export async function publishDone(context: common.UIAbilityContext, title: string): Promise<void> {
  const label: string = title.length > 0 ? title : t('当前对话');
  await publish(context, label + t(' · 回复已完成'), false);
}

/** Clears the reminder when the user comes back to the app. */
export async function clearGenerationNotification(): Promise<void> {
  try {
    await notificationManager.cancel(GENERATION_NOTIFICATION_ID);
  } catch (e) {
    // Nothing was published.
  }
}
