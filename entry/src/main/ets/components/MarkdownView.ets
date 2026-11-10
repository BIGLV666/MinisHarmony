import { pasteboard } from '@kit.BasicServicesKit';
import { common, ConfigurationConstant, Want } from '@kit.AbilityKit';
import {
  MdBlock,
  MdBlockKind,
  MdInline,
  isOpenableUrl,
  parseInline,
  parseMarkdown
} from '../core/Markdown';
import { scaleFont } from '../core/Types';
import { latexToText } from '../core/Latex';
import { MathBlockView } from './MathBlockView';
import {
  CodeSegment,
  TOKEN_COMMENT,
  TOKEN_FUNCTION,
  TOKEN_KEYWORD,
  TOKEN_NUMBER,
  TOKEN_STRING,
  highlightCode
} from '../core/CodeHighlight';
import { t } from '../core/I18n';
import { InlineMathBitmap, InlineMathCache } from '../service/InlineMathCache';
import {
  BROWSER_ARTIFACT_DIR,
  MINIS_ATTACHMENTS,
  MINIS_BROWSER,
  MINIS_WORKSPACE,
  MinisResource,
  parseMinisResource
} from '../core/MinisResource';
import { normalizeRelativePath } from '../core/Workspace';
import { AttachmentStore } from '../service/AttachmentStore';

@Component
export struct MarkdownView {
  @StorageProp('i18nVersion') i18nVersion: number = 0;
  @Prop @Watch('onTextChanged') text: string = '';
  @StorageProp('accentColor') accent: string = '#2F6BFF';
  @StorageProp('fontScale') fontScale: number = 1;
  /** When set, http(s) links open in the in-app browser. */
  onOpenLink: ((url: string) => void) | null = null;
  /** When set, `minis://workspace/...` links open a workspace preview. */
  onOpenMinis: ((resource: MinisResource) => void) | null = null;
  /**
   * Offscreen snapshot cards cannot host ArkWeb, so display math falls back to
   * the Unicode approximation there. The interactive chat view keeps KaTeX.
   */
  @Prop plainMath: boolean = false;
  @State blocks: MdBlock[] = [];
  @State mathImages: Map<string, InlineMathBitmap> = new Map();
  private dark: boolean = false;
  private gone: boolean = false;

  aboutToAppear(): void {
    this.gone = false;
    this.dark = this.isDark();
    this.blocks = parseMarkdown(this.text);
    this.requestInlineMath();
  }

  onTextChanged(): void {
    this.blocks = parseMarkdown(this.text);
    this.requestInlineMath();
  }

  aboutToDisappear(): void {
    this.gone = true;
  }

  private isDark(): boolean {
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      return context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } catch (e) {
      return false;
    }
  }

  private requestMathSegment(latex: string, size: number, seen: Set<string>): void {
    const key: string = InlineMathCache.keyFor(latex, size, this.dark);
    if (seen.has(key) || this.mathImages.has(key)) {
      return;
    }
    seen.add(key);
    InlineMathCache.request(latex, size, this.dark,
      (bitmap: InlineMathBitmap | null): void => {
        if (bitmap === null || this.gone) {
          return;
        }
        const next: Map<string, InlineMathBitmap> = new Map(this.mathImages);
        next.set(key, bitmap);
        this.mathImages = next;
      });
  }

  /**
   * Kick off KaTeX rendering for every inline formula in the message. The
   * text keeps its Unicode approximation until the bitmap arrives, so a
   * failing/slow render never blanks the paragraph.
   */
  private requestInlineMath(): void {
    if (this.plainMath || this.text.indexOf('$') < 0) {
      return;
    }
    const seen: Set<string> = new Set();
    for (let i = 0; i < this.blocks.length; i++) {
      const block: MdBlock = this.blocks[i];
      if (block.kind === MdBlockKind.Table) {
        const rows: string[][] = block.rows !== undefined ? block.rows : [];
        const cellSize: number = scaleFont(13, this.fontScale);
        for (let r = 0; r < rows.length; r++) {
          for (let c = 0; c < rows[r].length; c++) {
            const cells: MdInline[] = parseInline(rows[r][c]);
            for (let k = 0; k < cells.length; k++) {
              const math: string | undefined = cells[k].math;
              if (math !== undefined && math.length > 0) {
                this.requestMathSegment(math, cellSize, seen);
              }
            }
          }
        }
        continue;
      }
      if (block.kind === MdBlockKind.Code || block.kind === MdBlockKind.Math ||
        block.kind === MdBlockKind.Image || block.kind === MdBlockKind.Divider) {
        continue;
      }
      const base: number = block.kind === MdBlockKind.Heading
        ? this.headingSize(block.level) : 15;
      const size: number = scaleFont(base, this.fontScale);
      const segments: MdInline[] = parseInline(block.text);
      for (let j = 0; j < segments.length; j++) {
        const math: string | undefined = segments[j].math;
        if (math !== undefined && math.length > 0) {
          this.requestMathSegment(math, size, seen);
        }
      }
    }
  }

  private syntaxColor(kind: string): ResourceColor {
    if (kind === TOKEN_KEYWORD) {
      return $r('app.color.syntax_keyword');
    }
    if (kind === TOKEN_STRING) {
      return $r('app.color.syntax_string');
    }
    if (kind === TOKEN_COMMENT) {
      return $r('app.color.syntax_comment');
    }
    if (kind === TOKEN_NUMBER) {
      return $r('app.color.syntax_number');
    }
    if (kind === TOKEN_FUNCTION) {
      return $r('app.color.syntax_function');
    }
    return $r('app.color.text_primary');
  }

  private headingSize(level: number): number {
    if (level <= 1) {
      return scaleFont(22, this.fontScale);
    }
    if (level === 2) {
      return scaleFont(19, this.fontScale);
    }
    if (level === 3) {
      return scaleFont(17, this.fontScale);
    }
    return scaleFont(15, this.fontScale);
  }

  private copy(text: string): void {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.getUIContext().getPromptAction().showToast({ message: t('已复制') });
    }).catch((error: Error) => {
      this.getUIContext().getPromptAction().showToast({ message: t('复制失败') });
    });
  }

  /** In-app browser when the host provides a handler, system browser otherwise. */
  private openLink(url: string): void {
    const resource: MinisResource | null = parseMinisResource(url);
    if (resource !== null) {
      if (this.onOpenMinis !== null) {
        this.onOpenMinis(resource);
      } else {
        this.getUIContext().getPromptAction().showToast({ message: t('不支持的链接类型') });
      }
      return;
    }
    if (!isOpenableUrl(url)) {
      this.getUIContext().getPromptAction().showToast({ message: t('不支持的链接类型') });
      return;
    }
    const lower: string = url.toLowerCase();
    const isWeb: boolean = lower.indexOf('http://') === 0 || lower.indexOf('https://') === 0;
    if (this.onOpenLink !== null && isWeb) {
      this.onOpenLink(url);
      return;
    }
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    };
    context.startAbility(want).catch((error: Error) => {
      this.getUIContext().getPromptAction().showToast({ message: t('没有可打开该链接的应用') });
    });
  }

  @Builder
  inlineText(text: string, fontSize: number, color: ResourceColor, weight: FontWeight) {
    Text() {
      ForEach(parseInline(text), (segment: MdInline, index: number) => {
        if (segment.math !== undefined && segment.math.length > 0 && !this.plainMath &&
          this.mathImages.get(InlineMathCache.keyFor(segment.math,
            scaleFont(fontSize, this.fontScale), this.dark)) !== undefined) {
          ImageSpan(this.mathImages.get(InlineMathCache.keyFor(segment.math,
            scaleFont(fontSize, this.fontScale), this.dark))!.pixelMap)
            .width(px2vp(this.mathImages.get(InlineMathCache.keyFor(segment.math,
              scaleFont(fontSize, this.fontScale), this.dark))!.widthPx))
            .height(px2vp(this.mathImages.get(InlineMathCache.keyFor(segment.math,
              scaleFont(fontSize, this.fontScale), this.dark))!.heightPx))
            .verticalAlign(ImageSpanAlignment.BASELINE)
            .objectFit(ImageFit.Contain)
        } else {
          Span(segment.text)
            .fontWeight(segment.bold ? FontWeight.Bold : weight)
            .fontStyle(segment.italic ? FontStyle.Italic : FontStyle.Normal)
            .fontColor(segment.code ? this.accent : color)
            .fontFamily(segment.code ? 'monospace' : 'HarmonyOS Sans')
            .decoration({ type: segment.link.length > 0 ? TextDecorationType.Underline : TextDecorationType.None })
            .onClick(() => {
              if (segment.link.length > 0) {
                this.openLink(segment.link);
              }
            })
        }
      }, (segment: MdInline, index: number) => {
        const latex: string = segment.math !== undefined ? segment.math : '';
        const rendered: boolean = latex.length > 0 && !this.plainMath &&
          this.mathImages.get(InlineMathCache.keyFor(latex,
            scaleFont(fontSize, this.fontScale), this.dark)) !== undefined;
        return index.toString() + ':' + (rendered ? 'math' : 'text') + ':' +
          (latex.length > 0 ? latex : segment.text);
      })
    }
    .fontSize(scaleFont(fontSize, this.fontScale))
    .fontColor(color)
    .lineHeight(scaleFont(fontSize * 1.62, this.fontScale))
    .width('100%')
    .copyOption(CopyOptions.LocalDevice)
  }

  private tableRows(block: MdBlock): string[][] {
    return block.rows !== undefined ? block.rows : [];
  }

  @Builder
  tableCell(text: string, header: boolean) {
    Text() {
      ForEach(parseInline(text), (segment: MdInline, index: number) => {
        if (segment.math !== undefined && segment.math.length > 0 && !this.plainMath &&
          this.mathImages.get(InlineMathCache.keyFor(segment.math,
            scaleFont(13, this.fontScale), this.dark)) !== undefined) {
          ImageSpan(this.mathImages.get(InlineMathCache.keyFor(segment.math,
            scaleFont(13, this.fontScale), this.dark))!.pixelMap)
            .width(px2vp(this.mathImages.get(InlineMathCache.keyFor(segment.math,
              scaleFont(13, this.fontScale), this.dark))!.widthPx))
            .height(px2vp(this.mathImages.get(InlineMathCache.keyFor(segment.math,
              scaleFont(13, this.fontScale), this.dark))!.heightPx))
            .verticalAlign(ImageSpanAlignment.BASELINE)
            .objectFit(ImageFit.Contain)
        } else {
          Span(segment.text)
            .fontWeight(segment.bold || header ? FontWeight.Bold : FontWeight.Normal)
            .fontStyle(segment.italic ? FontStyle.Italic : FontStyle.Normal)
            .fontColor(segment.code ? this.accent : $r('app.color.text_primary'))
            .decoration({ type: segment.link.length > 0 ? TextDecorationType.Underline : TextDecorationType.None })
            .onClick(() => {
              if (segment.link.length > 0) {
                this.openLink(segment.link);
              }
            })
        }
      }, (segment: MdInline, index: number) => {
        const latex: string = segment.math !== undefined ? segment.math : '';
        const rendered: boolean = latex.length > 0 && !this.plainMath &&
          this.mathImages.get(InlineMathCache.keyFor(latex,
            scaleFont(13, this.fontScale), this.dark)) !== undefined;
        return index.toString() + ':' + (rendered ? 'math' : 'text') + ':' +
          (latex.length > 0 ? latex : segment.text);
      })
    }
    .fontSize(scaleFont(13, this.fontScale))
    .fontColor($r('app.color.text_primary'))
    .lineHeight(scaleFont(19, this.fontScale))
    .layoutWeight(1)
    .padding({ left: 9, right: 9, top: 7, bottom: 7 })
    .backgroundColor(header ? $r('app.color.surface_alt') : $r('app.color.surface'))
  }

  @Builder
  tableBlock(block: MdBlock) {
    Column() {
      ForEach(this.tableRows(block), (row: string[], rowIndex: number) => {
        Row() {
          ForEach(row, (cell: string, cellIndex: number) => {
            this.tableCell(cell, rowIndex === 0)
          }, (cell: string, cellIndex: number) => rowIndex.toString() + '-' + cellIndex.toString())
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        if (rowIndex === 0) {
          Divider()
            .color($r('app.color.border'))
        } else if (rowIndex < this.tableRows(block).length - 1) {
          Divider()
            .color($r('app.color.border'))
        }
      }, (row: string[], rowIndex: number) => rowIndex.toString() + row.join('|'))
    }
    .width('100%')
    .borderRadius(10)
    .border({ width: 1, color: $r('app.color.border') })
    .clip(true)
  }

  @Builder
  codeBlock(block: MdBlock) {
    Column() {
      Row() {
        Text(block.lang.length > 0 ? block.lang : 'code')
          .fontSize(scaleFont(11, this.fontScale))
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(t('复制'))
          .fontSize(scaleFont(11, this.fontScale))
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => this.copy(block.text))
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 6 })

      Text() {
        ForEach(highlightCode(block.text, block.lang), (segment: CodeSegment) => {
          Span(segment.text)
            .fontColor(this.syntaxColor(segment.kind))
        }, (segment: CodeSegment, index: number) =>
          index.toString() + ':' + segment.kind + ':' + segment.text.length.toString())
      }
      .fontSize(scaleFont(13, this.fontScale))
      .fontFamily('monospace')
      .fontColor($r('app.color.text_primary'))
      .lineHeight(scaleFont(20, this.fontScale))
      .width('100%')
      // Long unbroken tokens (URLs, base64) must wrap inside the bubble
      // instead of widening it past the screen edge.
      .wordBreak(WordBreak.BREAK_ALL)
      .padding({ left: 12, right: 12, bottom: 12 })
      .copyOption(CopyOptions.LocalDevice)
    }
    .width('100%')
    .backgroundColor($r('app.color.code_bg'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.border') })
  }

  @Builder
  listItem(block: MdBlock) {
    Row() {
      Text(block.ordered ? block.index.toString() + '.' : '•')
        .fontSize(scaleFont(15, this.fontScale))
        .fontColor($r('app.color.text_secondary'))
        .width(block.ordered ? 26 : 14)
      Column() {
        this.inlineText(block.text, 15, $r('app.color.text_primary'), FontWeight.Normal)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  quoteBlock(block: MdBlock) {
    Column() {
      this.inlineText(block.text, 15, $r('app.color.text_secondary'), FontWeight.Normal)
    }
    .width('100%')
    .padding({ left: 12, right: 8, top: 2, bottom: 2 })
    .border({ width: { left: 3 }, color: { left: $r('app.color.quote_bar') } })
  }

  /**
   * Turn an image link into something ArkUI can load. Workspace/attachment
   * resources stay inside the app sandbox; bare relative paths are treated as
   * workspace files (the same rule the agent uses for generated images).
   */
  private imageSource(url: string): string {
    const resource: MinisResource | null = parseMinisResource(url);
    if (resource !== null) {
      if (resource.scope === MINIS_WORKSPACE) {
        const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
        return 'file://' + context.filesDir + '/workspace/' + resource.path;
      }
      if (resource.scope === MINIS_ATTACHMENTS) {
        return 'file://' + AttachmentStore.absolutePath(resource.path);
      }
      if (resource.scope === MINIS_BROWSER) {
        const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
        return 'file://' + context.filesDir + '/workspace/' +
          BROWSER_ARTIFACT_DIR + '/' + resource.path;
      }
      return '';
    }
    const lower: string = url.toLowerCase();
    if (lower.indexOf('http://') === 0 || lower.indexOf('https://') === 0 ||
      lower.indexOf('data:image/') === 0) {
      return url;
    }
    const relative: string | null = normalizeRelativePath(url);
    if (relative !== null && relative.length > 0) {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      return 'file://' + context.filesDir + '/workspace/' + relative;
    }
    return '';
  }

  @Builder
  imageBlock(block: MdBlock) {
    Image(this.imageSource(block.imageUrl !== undefined ? block.imageUrl : ''))
      .width('100%')
      .constraintSize({ maxHeight: 360 })
      .objectFit(ImageFit.Contain)
      .borderRadius(10)
      .backgroundColor($r('app.color.surface_alt'))
      .alt(block.imageAlt !== undefined ? block.imageAlt : '')
      .draggable(false)
  }

  @Builder
  mathBlock(block: MdBlock) {
    if (this.plainMath) {
      Text(latexToText(block.raw !== undefined ? block.raw : block.text))
        .fontSize(scaleFont(15, this.fontScale))
        .fontFamily('monospace')
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
        .width('100%')
    } else {
      MathBlockView({
        source: block.raw !== undefined ? block.raw : block.text
      })
    }
  }

  @Builder
  renderBlock(block: MdBlock) {
    if (block.kind === MdBlockKind.Code) {
      this.codeBlock(block)
    } else if (block.kind === MdBlockKind.Heading) {
      Column() {
        this.inlineText(block.text, this.headingSize(block.level), $r('app.color.text_primary'), FontWeight.Bold)
      }
      .width('100%')
      .margin({ top: block.level <= 2 ? 10 : 4, bottom: 2 })
    } else if (block.kind === MdBlockKind.ListItem) {
      this.listItem(block)
    } else if (block.kind === MdBlockKind.Quote) {
      this.quoteBlock(block)
    } else if (block.kind === MdBlockKind.Table) {
      this.tableBlock(block)
    } else if (block.kind === MdBlockKind.Math) {
      this.mathBlock(block)
    } else if (block.kind === MdBlockKind.Image) {
      this.imageBlock(block)
    } else if (block.kind === MdBlockKind.Divider) {
      Divider()
        .color($r('app.color.border'))
        .margin({ top: 8, bottom: 8 })
    } else {
      this.inlineText(block.text, 15, $r('app.color.text_primary'), FontWeight.Normal)
    }
  }

  build() {
    Column({ space: 8 }) {
      ForEach(this.blocks, (block: MdBlock, index: number) => {
        this.renderBlock(block)
      }, (block: MdBlock, index: number) => index.toString() + block.kind + block.text.length)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
