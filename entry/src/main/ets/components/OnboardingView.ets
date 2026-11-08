import { OPENCODE_GO_BASE } from '../core/Types';

/**
 * First-run guide. It only collects the API key; every other option stays at
 * its safe default and can be changed later in Settings. Skipping marks the
 * guide as seen so it never blocks the app again.
 */
@Component
export struct OnboardingView {
  @Prop initialKey: string = '';
  onFinish: (apiKey: string) => void = (apiKey: string) => {
  };
  onSkip: () => void = () => {
  };

  @State step: number = 0;
  @State apiKey: string = '';
  @State showKey: boolean = false;

  aboutToAppear(): void {
    this.apiKey = this.initialKey;
  }

  @Builder
  stepDots() {
    Row({ space: 6 }) {
      ForEach([0, 1, 2], (index: number) => {
        Text('')
          .width(index === this.step ? 18 : 6)
          .height(6)
          .borderRadius(3)
          .backgroundColor(index === this.step
            ? $r('app.color.accent')
            : $r('app.color.border'))
      }, (index: number) => index.toString() + ':' + this.step.toString())
    }
    .width('100%')
  }

  @Builder
  welcome() {
    Column({ space: 12 }) {
      Text('Minis Harmony')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text('为鸿蒙平板打造的 OpenCode Go 客户端')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Column({ space: 8 }) {
        Text('· 流式对话、思考过程与工具调用循环')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Text('· 会话、工作区与密钥都保存在本机')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Text('· 工具默认只读，写入与记忆需手动开启')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  connect() {
    Column({ space: 10 }) {
      Text('连接服务')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text('当前预设：OpenCode Go')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
      Text(OPENCODE_GO_BASE)
        .fontSize(10)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 6 }) {
        TextInput({
          text: this.apiKey,
          placeholder: '粘贴 API Key'
        })
          .layoutWeight(1)
          .height(40)
          .type(this.showKey ? InputType.Normal : InputType.Password)
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(9)
          .onChange((value: string) => {
            this.apiKey = value;
          })
        Button(this.showKey ? '隐藏' : '显示', { type: ButtonType.Normal })
          .height(40)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(9)
          .onClick(() => {
            this.showKey = !this.showKey;
          })
      }
      .width('100%')

      Text('Key 存放在系统 Asset Store（不可用时回退为本地偏好），不会上传到其他服务。也可以先跳过，稍后在设置里填写。')
        .fontSize(10)
        .fontColor($r('app.color.text_tertiary'))
        .lineHeight(14)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ready() {
    Column({ space: 12 }) {
      Text('可以开始了')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text(this.apiKey.trim().length > 0
        ? 'API Key 会随「开始使用」一起保存。'
        : '还没有填写 API Key，可以稍后在设置里补充。')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(18)
      Column({ space: 7 }) {
        Text('· 设置 → 工具与沙箱：开启写入、记忆或远程工具服务')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
        Text('· 长按会话：置顶、归档、导出 Markdown / JSON')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
        Text('· 输入 /help 查看全部斜杠命令')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
      Column({ space: 14 }) {
        Row() {
          this.stepDots()
          Blank()
          Text('跳过')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .onClick(() => this.onSkip())
        }
        .width('100%')

        if (this.step === 0) {
          this.welcome()
        } else if (this.step === 1) {
          this.connect()
        } else {
          this.ready()
        }

        Row({ space: 10 }) {
          if (this.step > 0) {
            Button('上一步', { type: ButtonType.Normal })
              .layoutWeight(1)
              .height(40)
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(11)
              .onClick(() => {
                this.step--;
              })
          }
          Button(this.step < 2 ? '下一步' : '开始使用', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(40)
            .fontSize(13)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor($r('app.color.accent'))
            .borderRadius(11)
            .onClick(() => {
              if (this.step < 2) {
                this.step++;
              } else {
                this.onFinish(this.apiKey.trim());
              }
            })
        }
        .width('100%')
      }
      .width('86%')
      .constraintSize({ maxWidth: 420 })
      .padding(22)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(20)
      .border({ width: 1, color: $r('app.color.border') })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }
}
