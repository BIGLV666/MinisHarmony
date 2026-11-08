import { common } from '@kit.AbilityKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScheduledTask, taskNotificationContent, taskTitle } from '../core/ScheduledTask';

export interface ReminderOutcome {
  ok: boolean;
  message: string;
  reminderId: number;
}

/**
 * Publish a one-shot calendar reminder. Tapping the notification launches the
 * app with `minis://task/<id>` so the prompt can be restored into the
 * composer. The reminder itself never sends a request.
 *
 * Requires `ohos.permission.PUBLISH_AGENT_REMINDER` (normal permission).
 */
export async function scheduleTaskReminder(
  context: common.UIAbilityContext,
  task: ScheduledTask
): Promise<ReminderOutcome> {
  const date: Date = new Date(task.at);
  try {
    const request: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: {
        year: date.getFullYear(),
        month: date.getMonth() + 1,
        day: date.getDate(),
        hour: date.getHours(),
        minute: date.getMinutes(),
        second: 0
      },
      title: 'MinisHarmony · ' + taskTitle(task.prompt),
      content: taskNotificationContent(task.prompt),
      expiredContent: '定时任务时间已到',
      snoozeTimes: 0,
      ringDuration: 2,
      wantAgent: {
        pkgName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name,
        uri: 'minis://task/' + task.id
      }
    };
    const reminderId: number = await reminderAgentManager.publishReminder(request);
    return { ok: true, message: '', reminderId: reminderId };
  } catch (e) {
    const error: BusinessError = e as BusinessError;
    return {
      ok: false,
      message: '创建提醒失败：' + error.message,
      reminderId: 0
    };
  }
}

/** Best effort: a reminder that already fired or was removed cannot fail the UI. */
export async function cancelTaskReminder(reminderId: number): Promise<void> {
  if (reminderId <= 0) {
    return;
  }
  try {
    await reminderAgentManager.cancelReminder(reminderId);
  } catch (e) {
    // Nothing to cancel.
  }
}
