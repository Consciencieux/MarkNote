import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { RecentDocument, RecoveryData } from '../model/Document';

const RECENT_KEY: string = 'recent_files';
const THEME_KEY: string = 'color_choice';
const DRAFT: string = '/unsaved-draft.json';
const TEMP: string = '/unsaved-draft.tmp';

export class LocalState {
  static async readTheme(context: common.UIAbilityContext): Promise<string> {
    const store = await preferences.getPreferences(context, 'marknote-settings');
    const value = await store.get(THEME_KEY, 'system') as string;
    return value === 'light' || value === 'dark' ? value : 'system';
  }

  static async writeTheme(context: common.UIAbilityContext, choice: string): Promise<void> {
    const store = await preferences.getPreferences(context, 'marknote-settings');
    await store.put(THEME_KEY, choice);
    await store.flush();
  }

  static async readRecent(context: common.UIAbilityContext): Promise<RecentDocument[]> {
    const store = await preferences.getPreferences(context, 'marknote-settings');
    const encoded = await store.get(RECENT_KEY, '[]') as string;
    try {
      const parsed = JSON.parse(encoded) as RecentDocument[];
      if (!Array.isArray(parsed)) return [];
      return parsed.filter((value: RecentDocument) =>
        typeof value.uri === 'string' && value.uri.length > 0 && typeof value.name === 'string');
    } catch {
      return [];
    }
  }

  static async addRecent(context: common.UIAbilityContext, uri: string, filename: string): Promise<RecentDocument[]> {
    const previous = await LocalState.readRecent(context);
    const updated: RecentDocument[] = [new RecentDocument(uri, filename)];
    for (const recent of previous) {
      if (recent.uri !== uri && updated.length < 12) updated.push(recent);
    }
    const store = await preferences.getPreferences(context, 'marknote-settings');
    await store.put(RECENT_KEY, JSON.stringify(updated));
    await store.flush();
    return updated;
  }

  static async removeRecent(context: common.UIAbilityContext, uri: string): Promise<RecentDocument[]> {
    const previous = await LocalState.readRecent(context);
    const updated: RecentDocument[] = [];
    for (const recent of previous) {
      if (recent.uri !== uri) updated.push(recent);
    }
    const store = await preferences.getPreferences(context, 'marknote-settings');
    await store.put(RECENT_KEY, JSON.stringify(updated));
    await store.flush();
    return updated;
  }

  static readDraft(context: common.UIAbilityContext): RecoveryData | null {
    try {
      const text = fileIo.readTextSync(context.filesDir + DRAFT);
      const parsed = JSON.parse(text) as RecoveryData;
      if (typeof parsed.text !== 'string' || typeof parsed.savedText !== 'string' ||
          typeof parsed.name !== 'string' || typeof parsed.uri !== 'string') return null;
      if (typeof parsed.encoding !== 'string' || parsed.encoding.length === 0) parsed.encoding = 'utf-8';
      if (typeof parsed.lineEndings !== 'string') parsed.lineEndings = '';
      if (parsed.newline !== '\n' && parsed.newline !== '\r\n' && parsed.newline !== 'mixed') parsed.newline = '\n';
      if (typeof parsed.fingerprint !== 'string') parsed.fingerprint = '';
      if (typeof parsed.formatId !== 'string') parsed.formatId = '';
      parsed.writable = parsed.writable === true;
      parsed.persistent = parsed.persistent === true;
      if (parsed.text === parsed.savedText) return null;
      return parsed;
    } catch {
      return null;
    }
  }

  static writeDraft(context: common.UIAbilityContext, draft: RecoveryData): void {
    const temporary = context.filesDir + TEMP;
    const target = context.filesDir + DRAFT;
    const file = fileIo.openSync(temporary, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
    try {
      fileIo.truncateSync(file.fd, 0);
      const data = new util.TextEncoder().encodeInto(JSON.stringify(draft));
      let offset = 0;
      while (offset < data.length) {
        const written = fileIo.writeSync(file.fd, data.slice(offset).buffer);
        if (written <= 0) throw new Error('草稿写入中断');
        offset += written;
      }
      fileIo.fsyncSync(file.fd);
    } finally {
      fileIo.closeSync(file);
    }
    fileIo.renameSync(temporary, target);
  }

  static clearDraft(context: common.UIAbilityContext): void {
    try { fileIo.unlinkSync(context.filesDir + DRAFT); } catch { /* No draft yet. */ }
  }
}
