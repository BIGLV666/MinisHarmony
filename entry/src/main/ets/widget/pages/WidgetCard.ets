import { t } from '../../core/I18n';
/**
 * 2x2 home-screen card. Values come from the binding data the form ability
 * provides; tapping the card opens the app on the current conversation.
 */
@Entry
@Component
struct WidgetCard {
  @LocalStorageProp('title') title: string = 'Minis';
  @LocalStorageProp('body') body: string = t('打开应用开始新对话');
  @LocalStorageProp('hint') hint: string = '';

  build() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Image($r('app.media.app_icon'))
          .width(16)
          .height(16)
          .borderRadius(4)
        Text('Minis')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        if (this.hint.length > 0) {
          Text(this.hint)
            .fontSize(10)
            .fontColor($r('app.color.accent'))
        }
      }
      .width('100%')

      Text(this.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(this.body)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(15)
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        moduleName: 'entry'
      });
    })
  }
}
