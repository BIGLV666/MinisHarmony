import { BUILTIN_MODELS, ModelInfo } from '../core/Types';
import { capsForModel, capsLabel } from '../core/ModelCaps';
import { t } from '../core/I18n';

@Component
export struct ModelPicker {
  @StorageProp('i18nVersion') i18nVersion: number = 0;
  @Prop currentId: string = '';
  onPick: (id: string) => void = (id: string) => {
  };
  onClose: () => void = () => {
  };
  @State custom: string = '';

  @Builder
  modelRow(item: ModelInfo) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(item.name)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
        Text(item.id + (item.note.length > 0 ? t(' · ') + t(item.note) : '') +
          t(' · ') + capsLabel(capsForModel(item.id)))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.currentId === item.id) {
        Text('✓')
          .fontSize(13)
          .fontColor($r('app.color.accent'))
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 9, bottom: 9 })
    .borderRadius(9)
    .backgroundColor(this.currentId === item.id ? $r('app.color.accent_soft') : Color.Transparent)
    .onClick(() => this.onPick(item.id))
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
        .onClick(() => this.onClose())

      Column() {
        Row() {
          Column({ space: 2 }) {
            Text(t('选择模型'))
              .fontSize(19)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text(t('OpenCode Go 常用模型'))
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text('✕')
            .fontSize(17)
            .fontColor($r('app.color.text_secondary'))
            .padding(6)
            .onClick(() => this.onClose())
        }
        .width('100%')
        .margin({ bottom: 10 })

        List({ space: 2 }) {
          ForEach(BUILTIN_MODELS, (item: ModelInfo) => {
            ListItem() {
              this.modelRow(item)
            }
          }, (item: ModelInfo) => item.id)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)

        Column({ space: 8 }) {
          Row({ space: 8 }) {
            TextInput({ text: this.custom, placeholder: t('自定义模型 ID') })
              .layoutWeight(1)
              .height(40)
              .fontSize(12)
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(9)
              .onChange((value: string) => {
                this.custom = value;
              })
            Button(t('使用'))
              .height(40)
              .fontSize(12)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor(this.custom.trim().length > 0 ? $r('app.color.accent') : $r('app.color.surface_alt'))
              .borderRadius(9)
              .enabled(this.custom.trim().length > 0)
              .onClick(() => this.onPick(this.custom.trim()))
          }
          .width('100%')

          Text(t('更多模型可在设置中获取；不同区域与隐私设置会影响可用模型。'))
            .fontSize(9)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
        .width('100%')
        .margin({ top: 10 })
      }
      .width('90%')
      .height('84%')
      .constraintSize({ maxWidth: 560 })
      .padding(18)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(20)
      .border({ width: 1, color: $r('app.color.border') })
    }
    .width('100%')
    .height('100%')
  }
}
