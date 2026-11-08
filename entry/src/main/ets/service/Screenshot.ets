import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { UIContext } from '@kit.ArkUI';
import { t } from '../core/I18n';

export interface ScreenshotOutcome {
  ok: boolean;
  message: string;
}

/**
 * Write already-encoded PNG bytes through the system document picker, the same
 * permission-free route used for JSON/Markdown exports.
 */
async function savePng(
  context: common.UIAbilityContext,
  fileName: string,
  data: ArrayBuffer
): Promise<ScreenshotOutcome> {
  try {
    const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName];
    options.fileSuffixChoices = ['PNG|.png'];
    const documentPicker: picker.DocumentViewPicker =
      new picker.DocumentViewPicker(context);
    const uris: string[] = await documentPicker.save(options);
    if (uris.length === 0) {
      return { ok: false, message: t('已取消保存截图') };
    }
    const file = fs.openSync(
      uris[0],
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
    );
    try {
      fs.writeSync(file.fd, data);
    } finally {
      fs.closeSync(file);
    }
    return { ok: true, message: t('已保存截图') };
  } catch (e) {
    const error: BusinessError = e as BusinessError;
    return { ok: false, message: t('保存截图失败：') + error.message };
  }
}

/**
 * Render an offscreen builder to a PNG and let the user pick a destination.
 * Rendering offscreen means a turn taller than the viewport is captured in
 * full instead of being clipped to what is currently scrolled into view.
 */
export async function saveShareCard(
  context: common.UIAbilityContext,
  ui: UIContext,
  builder: CustomBuilder,
  fileName: string
): Promise<ScreenshotOutcome> {
  let pixelMap: image.PixelMap | null = null;
  try {
    pixelMap = await ui.getComponentSnapshot().createFromBuilder(builder, 250, false);
  } catch (e) {
    const error: BusinessError = e as BusinessError;
    return { ok: false, message: t('截图失败：') + error.message };
  }
  const packer: image.ImagePacker = image.createImagePacker();
  try {
    const option: image.PackingOption = { format: 'image/png', quality: 100 };
    const data: ArrayBuffer = await packer.packToData(pixelMap, option);
    return await savePng(context, fileName, data);
  } catch (e) {
    const error: BusinessError = e as BusinessError;
    return { ok: false, message: t('编码截图失败：') + error.message };
  } finally {
    pixelMap.release();
    packer.release().catch(() => {
      // Releasing a short-lived packer is best effort.
    });
  }
}
