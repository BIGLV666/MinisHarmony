import {
  MAX_TASK_PROMPT,
  ScheduledTask,
  TaskRun,
  formatTaskTime,
  taskTitle,
  validateTaskAt
} from '../core/ScheduledTask';
import { t } from '../core/I18n';

const DAY_MS: number = 24 * 60 * 60 * 1000;

/**
 * Create and manage scheduled reminders.
 *
 * A scheduled task is only a notification: it never spends tokens on its own.
 * Tapping the reminder reopens the app with the prompt in the composer, and
 * the run history records what the reply was after the user sends it.
 */
@Component
export struct ScheduledTasksSheet {
  @StorageProp('i18nVersion') i18nVersion: number = 0;
  @Prop tasks: ScheduledTask[] = [];
  @Prop runs: TaskRun[] = [];
  onCreate: (prompt: string, at: number) => void = () => {
  };
  onCancelTask: (id: string) => void = () => {
  };
  onFill: (id: string) => void = () => {
  };
  onClearRuns: () => void = () => {
  };
  onClose: () => void = () => {
  };

  @State prompt: string = '';
  @State at: number = Date.now() + 60 * 60 * 1000;
  @State error: string = '';
  @State showHistory: boolean = false;

  private quick(hours: number): void {
    this.at = Date.now() + hours * 60 * 60 * 1000;
    this.error = '';
  }

  private quickAt(hour: number, dayOffset: number): void {
    const base: Date = new Date();
    const target: Date = new Date(
      base.getFullYear(), base.getMonth(), base.getDate() + dayOffset, hour, 0, 0, 0);
    this.at = target.getTime();
    this.error = '';
  }

  private create(): void {
    const prompt: string = this.prompt.trim();
    if (prompt.length === 0) {
      this.error = t('请填写到时间后要发送的提示词');
      return;
    }
    const reason: string = validateTaskAt(this.at, Date.now());
    if (reason.length > 0) {
      this.error = reason;
      return;
    }
    this.error = '';
    this.onCreate(prompt, this.at);
    this.prompt = '';
  }

  private statusOf(task: ScheduledTask, now: number): string {
    if (task.at > now) {
      return t('等待提醒');
    }
    if (task.triggeredAt > 0) {
      return t('已触发');
    }
    return t('已过期');
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Column({ space: 3 }) {
        Text(t('定时任务'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(t('到点提醒，点通知把提示词填回输入框'))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('✕')
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
        .padding(6)
        .onClick(() => this.onClose())
    }
    .width('100%')
  }

  @Builder
  composer() {
    Column({ space: 8 }) {
      TextArea({ text: this.prompt, placeholder: t('到时间后要发送的提示词，例如：总结今天的日程') })
        .width('100%')
        .height(84)
        .fontSize(13)
        .maxLength(MAX_TASK_PROMPT)
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(10)
        .onChange((value: string) => {
          this.prompt = value;
          this.error = '';
        })

      Row({ space: 6 }) {
        this.quickChip(t('1 小时后'), () => this.quick(1))
        this.quickChip(t('今晚 20:00'), () => this.quickAt(20, 0))
        this.quickChip(t('明早 09:00'), () => this.quickAt(9, 1))
      }
      .width('100%')

      DatePicker({
        start: new Date(),
        end: new Date(Date.now() + 365 * DAY_MS),
        selected: new Date(this.at)
      })
        .width('100%')
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(10)
        .onChange((value: DatePickerResult) => {
          const previous: Date = new Date(this.at);
          const year: number = value.year !== undefined ? value.year : previous.getFullYear();
          const month: number = value.month !== undefined ? value.month : previous.getMonth();
          const day: number = value.day !== undefined ? value.day : previous.getDate();
          this.at = new Date(year, month, day,
            previous.getHours(), previous.getMinutes(), 0, 0).getTime();
          this.error = '';
        })

      TimePicker({ selected: new Date(this.at) })
        .width('100%')
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(10)
        .onChange((value: TimePickerResult) => {
          const previous: Date = new Date(this.at);
          this.at = new Date(previous.getFullYear(), previous.getMonth(),
            previous.getDate(), value.hour, value.minute, 0, 0).getTime();
          this.error = '';
        })

      Row({ space: 8 }) {
        Text(t('提醒：') + formatTaskTime(this.at, Date.now()))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        Text(t('创建'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor($r('app.color.accent'))
          .borderRadius(9)
          .onClick(() => this.create())
      }
      .width('100%')

      if (this.error.length > 0) {
        Text(this.error)
          .fontSize(11)
          .fontColor($r('app.color.danger'))
          .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  quickChip(label: string, action: () => void) {
    Text(label)
      .fontSize(11)
      .fontColor($r('app.color.text_secondary'))
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor($r('app.color.surface_alt'))
      .borderRadius(8)
      .onClick(action)
  }

  @Builder
  taskRow(task: ScheduledTask) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text(taskTitle(task.prompt))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.statusOf(task, Date.now()))
          .fontSize(10)
          .fontColor(task.at > Date.now()
            ? $r('app.color.accent')
            : $r('app.color.text_tertiary'))
      }
      .width('100%')

      Row({ space: 10 }) {
        Text(formatTaskTime(task.at, Date.now()))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
          .layoutWeight(1)
        Text(t('填入'))
          .fontSize(11)
          .fontColor($r('app.color.accent'))
          .onClick(() => this.onFill(task.id))
        Text(t('删除'))
          .fontSize(11)
          .fontColor($r('app.color.danger'))
          .onClick(() => this.onCancelTask(task.id))
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(10)
    .borderRadius(9)
    .backgroundColor($r('app.color.surface_alt'))
  }

  @Builder
  taskList() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(t('已安排'))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        Text(this.showHistory ? t('隐藏历史') : t('运行历史 (') + this.runs.length.toString() + ')')
          .fontSize(10)
          .fontColor($r('app.color.accent'))
          .onClick(() => {
            this.showHistory = !this.showHistory;
          })
      }
      .width('100%')

      if (this.tasks.length === 0) {
        Text(t('还没有定时任务'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .padding({ top: 8, bottom: 8 })
      } else {
        ForEach(this.tasks, (task: ScheduledTask) => {
          this.taskRow(task)
        }, (task: ScheduledTask) => task.id + ':' + task.at.toString() +
          ':' + task.triggeredAt.toString())
      }
    }
    .width('100%')
  }

  @Builder
  history() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(t('运行历史'))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        if (this.runs.length > 0) {
          Text(t('清空'))
            .fontSize(10)
            .fontColor($r('app.color.danger'))
            .onClick(() => this.onClearRuns())
        }
      }
      .width('100%')

      if (this.runs.length === 0) {
        Text(t('任务提示词发送并完成后，这里会记录结果摘要'))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      } else {
        ForEach(this.runs, (run: TaskRun) => {
          Column({ space: 3 }) {
            Row({ space: 6 }) {
              Text(run.ok ? '✓' : '✕')
                .fontSize(10)
                .fontColor(run.ok ? $r('app.color.accent') : $r('app.color.danger'))
              Text(run.title)
                .fontSize(11)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(formatTaskTime(run.finishedAt, Date.now()))
                .fontSize(9)
                .fontColor($r('app.color.text_tertiary'))
            }
            .width('100%')
            if (run.summary.length > 0) {
              Text(run.summary)
                .fontSize(10)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .borderRadius(9)
          .backgroundColor($r('app.color.surface_alt'))
        }, (run: TaskRun) => run.id)
      }
    }
    .width('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
        .onClick(() => this.onClose())
      Scroll() {
        Column({ space: 14 }) {
          this.header()
          this.composer()
          this.taskList()
          if (this.showHistory) {
            this.history()
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('90%')
      .constraintSize({ maxWidth: 520, maxHeight: '86%' })
      .padding(18)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.border') })
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
  }
}
