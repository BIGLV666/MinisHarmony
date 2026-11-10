import { BUILTIN_MODELS, ModelInfo } from '../core/Types';
import { capsForModel, capsLabel } from '../core/ModelCaps';
import { ModelTestOutcome, modelTestLine } from '../core/ModelTest';
import { t } from '../core/I18n';
import { AttachmentStore } from '../service/AttachmentStore';

@Component
export struct ModelPicker {
  @StorageProp('i18nVersion') i18nVersion: number = 0;
  @Prop currentId: string = '';
  onPick: (id: string) => void = (id: string) => {
  };
  onClose: () => void = () => {
  };
  onTestModel: (id: string) => Promise<ModelTestOutcome> =
    async (id: string): Promise<ModelTestOutcome> => {
      return { ok: false, text: '', message: t('模型测试不可用'), elapsedMs: 0 };
    };
  /** Image generation is only offered for OpenAI-compatible presets. */
  @Prop imageTestAvailable: boolean = false;
  onTestImage: (id: string) => Promise<ModelTestOutcome> =
    async (id: string): Promise<ModelTestOutcome> => {
      return { ok: false, text: '', message: t('模型测试不可用'), elapsedMs: 0 };
    };
  @State custom: string = '';
  @State testIds: string[] = [];
  @State testLines: string[] = [];
  @State testingIds: string[] = [];
  @State imageIds: string[] = [];
  @State imageLines: string[] = [];
  @State imageUris: string[] = [];
  @State imageTestingIds: string[] = [];

  private testText(id: string): string {
    const at: number = this.testIds.indexOf(id);
    return at >= 0 ? this.testLines[at] : '';
  }

  private testing(id: string): boolean {
    return this.testingIds.indexOf(id) >= 0;
  }

  private setTestLine(id: string, line: string): void {
    const ids: string[] = this.testIds.slice();
    const lines: string[] = this.testLines.slice();
    const at: number = ids.indexOf(id);
    if (at >= 0) {
      lines[at] = line;
    } else {
      ids.push(id);
      lines.push(line);
    }
    this.testIds = ids;
    this.testLines = lines;
  }

  private async runTest(id: string): Promise<void> {
    if (id.trim().length === 0 || this.testing(id)) {
      return;
    }
    const testing: string[] = this.testingIds.slice();
    testing.push(id);
    this.testingIds = testing;
    this.setTestLine(id, t('测试中…'));
    const outcome: ModelTestOutcome = await this.onTestModel(id);
    const left: string[] = [];
    for (let i = 0; i < this.testingIds.length; i++) {
      if (this.testingIds[i] !== id) {
        left.push(this.testingIds[i]);
      }
    }
    this.testingIds = left;
    this.setTestLine(id, modelTestLine(outcome));
  }

  private imageText(id: string): string {
    const at: number = this.imageIds.indexOf(id);
    return at >= 0 ? this.imageLines[at] : '';
  }

  private imageUri(id: string): string {
    const at: number = this.imageIds.indexOf(id);
    return at >= 0 ? this.imageUris[at] : '';
  }

  private imageTesting(id: string): boolean {
    return this.imageTestingIds.indexOf(id) >= 0;
  }

  private setImageResult(id: string, line: string, uri: string): void {
    const ids: string[] = this.imageIds.slice();
    const lines: string[] = this.imageLines.slice();
    const uris: string[] = this.imageUris.slice();
    const at: number = ids.indexOf(id);
    if (at >= 0) {
      lines[at] = line;
      uris[at] = uri;
    } else {
      ids.push(id);
      lines.push(line);
      uris.push(uri);
    }
    this.imageIds = ids;
    this.imageLines = lines;
    this.imageUris = uris;
  }

  private async runImageTest(id: string): Promise<void> {
    if (id.trim().length === 0 || this.imageTesting(id)) {
      return;
    }
    const testing: string[] = this.imageTestingIds.slice();
    testing.push(id);
    this.imageTestingIds = testing;
    this.setImageResult(id, t('生成图片中…'), '');
    const outcome: ModelTestOutcome = await this.onTestImage(id);
    const left: string[] = [];
    for (let i = 0; i < this.imageTestingIds.length; i++) {
      if (this.imageTestingIds[i] !== id) {
        left.push(this.imageTestingIds[i]);
      }
    }
    this.imageTestingIds = left;
    const uri: string = outcome.imageUri !== undefined ? outcome.imageUri : '';
    this.setImageResult(id, modelTestLine(outcome), uri);
  }

  @Builder
  modelRow(item: ModelInfo) {
    Column({ space: 4 }) {
      Row({ space: 10 }) {
        Row({ space: 8 }) {
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
        .layoutWeight(1)
        .onClick(() => this.onPick(item.id))

        Row({ space: 6 }) {
          Text(this.testing(item.id) ? t('测试中…') : t('测试'))
            .fontSize(11)
            .fontColor(this.testing(item.id)
              ? $r('app.color.text_tertiary')
              : $r('app.color.text_secondary'))
            .padding({ left: 8, right: 8, top: 5, bottom: 5 })
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(7)
            .onClick(() => {
              this.runTest(item.id);
            })
          if (this.imageTestAvailable) {
            Text(this.imageTesting(item.id) ? t('生成中…') : t('图像'))
              .fontSize(11)
              .fontColor(this.imageTesting(item.id)
                ? $r('app.color.text_tertiary')
                : $r('app.color.text_secondary'))
              .padding({ left: 8, right: 8, top: 5, bottom: 5 })
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(7)
              .onClick(() => {
                this.runImageTest(item.id);
              })
          }
        }
      }
      .width('100%')

      if (this.testText(item.id).length > 0) {
        Text(this.testText(item.id))
          .fontSize(10)
          .fontColor(this.testText(item.id).startsWith(t('测试中…'))
            ? $r('app.color.text_tertiary')
            : $r('app.color.text_secondary'))
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (this.imageText(item.id).length > 0) {
        Text(this.imageText(item.id))
          .fontSize(10)
          .fontColor(this.imageTesting(item.id)
            ? $r('app.color.text_tertiary')
            : $r('app.color.text_secondary'))
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (this.imageUri(item.id).length > 0) {
        Image('file://' + AttachmentStore.imagePath(this.imageUri(item.id)))
          .width(140)
          .height(140)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 9, bottom: 9 })
    .borderRadius(9)
    .backgroundColor(this.currentId === item.id ? $r('app.color.accent_soft') : Color.Transparent)
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

          if (this.custom.trim().length > 0) {
            Row({ space: 8 }) {
              Text(this.testing(this.custom.trim())
                ? t('测试中…')
                : t('测试') + ' ' + this.custom.trim())
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .padding({ left: 9, right: 9, top: 6, bottom: 6 })
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(8)
                .onClick(() => {
                  this.runTest(this.custom.trim());
                })
              if (this.imageTestAvailable) {
                Text(this.imageTesting(this.custom.trim())
                  ? t('生成中…')
                  : t('图像'))
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .padding({ left: 9, right: 9, top: 6, bottom: 6 })
                  .backgroundColor($r('app.color.surface_alt'))
                  .borderRadius(8)
                  .onClick(() => {
                    this.runImageTest(this.custom.trim());
                  })
              }
              Text(this.testText(this.custom.trim()))
                .fontSize(10)
                .fontColor($r('app.color.text_tertiary'))
                .layoutWeight(1)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')

            if (this.imageText(this.custom.trim()).length > 0) {
              Text(this.imageText(this.custom.trim()))
                .fontSize(10)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            if (this.imageUri(this.custom.trim()).length > 0) {
              Image('file://' + AttachmentStore.imagePath(this.imageUri(this.custom.trim())))
                .width(140)
                .height(140)
                .borderRadius(8)
                .objectFit(ImageFit.Cover)
            }
          }

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
