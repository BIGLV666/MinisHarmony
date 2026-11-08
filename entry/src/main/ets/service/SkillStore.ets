import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import {
  SkillDoc,
  findSkill,
  parseSkillDoc,
  skillCatalogue,
  skillIdFromFile
} from '../core/SkillDoc';
import { t } from '../core/I18n';

const MAX_SKILL_BYTES: number = 512 * 1024;
const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');

/**
 * Skills live as `.md` files in the app sandbox. The catalogue is cached in
 * memory at startup and after every import/delete, so building the system
 * prompt stays synchronous on the send path.
 */
export class SkillStore {
  private static dir: string = '';
  private static cache: SkillDoc[] = [];

  static init(dir: string): void {
    SkillStore.dir = dir;
    SkillStore.refresh();
  }

  static refresh(): void {
    const docs: SkillDoc[] = [];
    if (SkillStore.dir.length === 0) {
      SkillStore.cache = docs;
      return;
    }
    try {
      fs.mkdirSync(SkillStore.dir);
    } catch (e) {
      // Already exists.
    }
    try {
      const names: string[] = fs.listFileSync(SkillStore.dir);
      for (let i = 0; i < names.length; i++) {
        const name: string = names[i];
        if (!name.toLowerCase().endsWith('.md')) {
          continue;
        }
        const doc: SkillDoc | null = SkillStore.readFile(name);
        if (doc !== null) {
          docs.push(doc);
        }
      }
    } catch (e) {
      // Directory unavailable; keep whatever the cache has.
    }
    docs.sort((a: SkillDoc, b: SkillDoc): number => a.name.localeCompare(b.name));
    SkillStore.cache = docs;
  }

  private static readFile(fileName: string): SkillDoc | null {
    try {
      const path: string = SkillStore.dir + '/' + fileName;
      const stat = fs.statSync(path);
      if (stat.isDirectory() || stat.size > MAX_SKILL_BYTES) {
        return null;
      }
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        fs.readSync(file.fd, buffer);
      } finally {
        fs.closeSync(file);
      }
      const text: string = decoder.decodeToString(new Uint8Array(buffer));
      return parseSkillDoc(text, skillIdFromFile(fileName));
    } catch (e) {
      return null;
    }
  }

  static list(): SkillDoc[] {
    return SkillStore.cache.slice();
  }

  static get(id: string): SkillDoc | null {
    return findSkill(SkillStore.cache, id);
  }

  static block(enabledIds: string[]): string {
    if (enabledIds.length === 0) {
      return '';
    }
    const enabled: SkillDoc[] = [];
    for (let i = 0; i < SkillStore.cache.length; i++) {
      if (enabledIds.indexOf(SkillStore.cache[i].id) >= 0) {
        enabled.push(SkillStore.cache[i]);
      }
    }
    return skillCatalogue(enabled);
  }

  /** Import raw markdown under a unique id derived from the file name. */
  static importText(fileName: string, text: string): SkillDoc | null {
    if (SkillStore.dir.length === 0 || text.trim().length === 0 ||
      text.length > MAX_SKILL_BYTES) {
      return null;
    }
    try {
      fs.mkdirSync(SkillStore.dir);
    } catch (e) {
      // Already exists.
    }
    let id: string = skillIdFromFile(fileName);
    let attempt: number = 2;
    while (SkillStore.fileExists(id + '.md')) {
      id = skillIdFromFile(fileName) + '-' + attempt.toString();
      attempt++;
    }
    try {
      const file = fs.openSync(SkillStore.dir + '/' + id + '.md',
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, text);
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      return null;
    }
    SkillStore.refresh();
    return SkillStore.get(id);
  }

  static remove(id: string): boolean {
    if (SkillStore.dir.length === 0 || id.length === 0) {
      return false;
    }
    try {
      fs.unlinkSync(SkillStore.dir + '/' + id + '.md');
    } catch (e) {
      return false;
    }
    SkillStore.refresh();
    return true;
  }

  /** Ask for one `.md` file and import it; returns a message for a toast. */
  static async pickAndImport(context: common.UIAbilityContext): Promise<string> {
    try {
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['Markdown|.md'];
      const documentPicker: picker.DocumentViewPicker =
        new picker.DocumentViewPicker(context);
      const uris: string[] = await documentPicker.select(options);
      if (uris.length === 0) {
        return t('已取消导入');
      }
      const stat = fs.statSync(uris[0]);
      if (stat.size <= 0) {
        return t('技能文件是空的');
      }
      if (stat.size > MAX_SKILL_BYTES) {
        return t('技能文件超过 512 KB，拒绝导入');
      }
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      const file = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
      try {
        fs.readSync(file.fd, buffer);
      } finally {
        fs.closeSync(file);
      }
      const text: string = decoder.decodeToString(new Uint8Array(buffer));
      const doc: SkillDoc | null = SkillStore.importText(uris[0], text);
      return doc === null ? t('导入失败：无法写入应用目录') : t('已导入技能：') + doc.name;
    } catch (e) {
      return t('导入失败，请确认文件是 SKILL.md');
    }
  }

  private static fileExists(fileName: string): boolean {
    try {
      fs.accessSync(SkillStore.dir + '/' + fileName);
      return true;
    } catch (e) {
      return false;
    }
  }
}
