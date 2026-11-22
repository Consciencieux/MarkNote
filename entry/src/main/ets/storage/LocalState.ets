import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { RecentDocument, RecoveryData } from '../model/Document';
import { RecentEntry, removeRecentDocument, toggleFavoriteDocument, updateRecentDocument } from '../document/RecentOrder';
import { TextEncoding } from '../document/TextEncoding';
import { readDraftFile, writeDraftFile } from './DraftFile';
import { normalizeAppLanguage } from '../i18n/AppLanguage';

const RECENT_KEY: string = 'recent_files';
const THEME_KEY: string = 'color_choice';
const CODE_THEME_KEY: string = 'code_theme';
/**
 * 用户选择，含 `default`。系统偏好语言接口负责真正切换资源；
 * 其读取结果未说明会保留 `default`，不能单独用来区分“跟随系统”和已解析出的语言。
 */
const LANGUAGE_KEY: string = 'app_language';
const SORT_KEY: string = 'recent_sort';
const DRAFT: string = '/unsaved-draft.json';

interface CodedError {
  code?: number;
}

export class LocalState {
  static readCodeThemeSync(context: common.UIAbilityContext): string {
    try {
      const store = preferences.getPreferencesSync(context, { name: 'marknote-settings' });
      const value = store.getSync(CODE_THEME_KEY, 'github');
      return value === 'off' || value === 'atom' || value === 'vs' ? value : 'github';
    } catch { return 'github'; }
  }

  static writeCodeThemeSync(context: common.UIAbilityContext, choice: string): void {
    const store = preferences.getPreferencesSync(context, { name: 'marknote-settings' });
    store.putSync(CODE_THEME_KEY, choice);
    store.flushSync();
  }

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

  static readLanguageSync(context: common.UIAbilityContext): string {
    try {
      const store = preferences.getPreferencesSync(context, { name: 'marknote-settings' });
      const value = store.getSync(LANGUAGE_KEY, 'default');
      return normalizeAppLanguage(typeof value === 'string' ? value : 'default');
    } catch {
      return 'default';
    }
  }

  static writeLanguageSync(context: common.UIAbilityContext, choice: string): void {
    const store = preferences.getPreferencesSync(context, { name: 'marknote-settings' });
    store.putSync(LANGUAGE_KEY, normalizeAppLanguage(choice));
    store.flushSync();
  }

  static async readLanguage(context: common.UIAbilityContext): Promise<string> {
    const store = await preferences.getPreferences(context, 'marknote-settings');
    const value = await store.get(LANGUAGE_KEY, 'default') as string;
    return normalizeAppLanguage(value);
  }

  static async writeLanguage(context: common.UIAbilityContext, choice: string): Promise<void> {
    const store = await preferences.getPreferences(context, 'marknote-settings');
    await store.put(LANGUAGE_KEY, choice);
    await store.flush();
  }

  static async readRecent(context: common.UIAbilityContext): Promise<RecentDocument[]> {
    const store = await preferences.getPreferences(context, 'marknote-settings');
    const encoded = await store.get(RECENT_KEY, '[]') as string;
    try {
      const parsed = JSON.parse(encoded) as RecentDocument[];
      if (!Array.isArray(parsed)) return [];
      return parsed.filter((value: RecentDocument) =>
        value !== null && typeof value === 'object' &&
        typeof value.uri === 'string' && value.uri.length > 0 && typeof value.name === 'string')
        .map((value: RecentDocument): RecentDocument => {
          const item = new RecentDocument(value.uri, value.name);
          item.openedAt = Number.isFinite(value.openedAt) && value.openedAt > 0 ? value.openedAt : 0;
          item.modifiedAt = Number.isFinite(value.modifiedAt) && value.modifiedAt > 0 ? value.modifiedAt : 0;
          item.favorite = value.favorite === true;
          item.recent = value.recent !== false;
          return item;
        });
    } catch {
      return [];
    }
  }

  static async readSort(context: common.UIAbilityContext): Promise<string> {
    const store = await preferences.getPreferences(context, 'marknote-settings');
    const order = await store.get(SORT_KEY, 'modified') as string;
    return order === 'opened' || order === 'name' || order === 'type' ? order : 'modified';
  }

  static async writeSort(context: common.UIAbilityContext, order: string): Promise<void> {
    const store = await preferences.getPreferences(context, 'marknote-settings');
    await store.put(SORT_KEY, order);
    await store.flush();
  }

  static async addRecent(context: common.UIAbilityContext, uri: string, filename: string,
    modifiedAt: number, opened: boolean, previous: RecentDocument[]): Promise<RecentDocument[]> {
    const updated: RecentEntry[] = updateRecentDocument(previous, uri, filename, Date.now(), modifiedAt, opened);
    const store = await preferences.getPreferences(context, 'marknote-settings');
    await store.put(RECENT_KEY, JSON.stringify(updated));
    await store.flush();
    return updated as RecentDocument[];
  }

  static async removeRecent(context: common.UIAbilityContext, uri: string,
    previous: RecentDocument[], deleted: boolean): Promise<RecentDocument[]> {
    const updated: RecentEntry[] = removeRecentDocument(previous, uri, deleted);
    const store = await preferences.getPreferences(context, 'marknote-settings');
    await store.put(RECENT_KEY, JSON.stringify(updated));
    await store.flush();
    return updated as RecentDocument[];
  }

  static async toggleFavorite(context: common.UIAbilityContext, uri: string, filename: string,
    modifiedAt: number, previous: RecentDocument[]): Promise<RecentDocument[]> {
    const updated = toggleFavoriteDocument(previous, uri, filename, modifiedAt);
    const store = await preferences.getPreferences(context, 'marknote-settings');
    await store.put(RECENT_KEY, JSON.stringify(updated));
    await store.flush();
    return updated as RecentDocument[];
  }

  static async readDraft(context: common.UIAbilityContext): Promise<RecoveryData | null> {
    let parsed: RecoveryData;
    try {
      parsed = await readDraftFile(context.filesDir + DRAFT);
    } catch (error) {
      const coded = error as CodedError;
      if (coded && coded.code === 13900002) return null;
      throw error instanceof Error ? error : new Error('draft read failed');
    }
    try {
      if (!parsed || typeof parsed.text !== 'string' || typeof parsed.savedText !== 'string' ||
          typeof parsed.name !== 'string' || typeof parsed.uri !== 'string') throw new Error('invalid draft');
      if (typeof parsed.encoding !== 'string' || parsed.encoding.length === 0) parsed.encoding = 'utf-8';
      if (typeof parsed.lineEndings !== 'string') parsed.lineEndings = '';
      if (parsed.newline !== '\n' && parsed.newline !== '\r' && parsed.newline !== '\r\n' &&
        parsed.newline !== 'mixed') {
        parsed.newline = '\n';
      }
      if (typeof parsed.fingerprint !== 'string') parsed.fingerprint = '';
      if (typeof parsed.formatId !== 'string') parsed.formatId = '';
      parsed.hasBom = parsed.hasBom === true;
      parsed.writable = parsed.writable === true;
      parsed.persistent = parsed.persistent === true;
      parsed.writeUncertain = parsed.writeUncertain === true;
      if (typeof parsed.pendingWriteText !== 'string') parsed.pendingWriteText = '';
      if (typeof parsed.pendingWriteUri !== 'string') parsed.pendingWriteUri = '';
      if (parsed.editedEndings !== undefined && (typeof parsed.editedEndings !== 'string' ||
        parsed.newline !== 'mixed' || /[^nrc]/.test(parsed.editedEndings) ||
        parsed.editedEndings.length !== TextEncoding.lineBreakCount(parsed.text))) throw new Error('invalid draft endings');
      if (parsed.text === parsed.savedText && !parsed.writeUncertain &&
        (parsed.editedEndings ?? parsed.lineEndings) === parsed.lineEndings) return null;
      return parsed;
    } catch {
      const error = new Error('invalid draft');
      error.name = 'InvalidDraftError';
      throw error;
    }
  }

  static isInvalidDraft(error: Object): boolean {
    return error instanceof Error && error.name === 'InvalidDraftError';
  }

  /** Keep the unreadable bytes in a separate file before allowing a new recovery slot. */
  static async quarantineDraft(context: common.UIAbilityContext): Promise<string> {
    let index = 0;
    let destination = context.filesDir + '/unsaved-draft-corrupt-' + index + '.json';
    while (await fileIo.access(destination)) {
      index++;
      destination = context.filesDir + '/unsaved-draft-corrupt-' + index + '.json';
    }
    await fileIo.rename(context.filesDir + DRAFT, destination);
    return destination;
  }

  static async writeDraft(context: common.UIAbilityContext, draft: RecoveryData): Promise<void> {
    const file = new fileIo.AtomicFile(context.filesDir + DRAFT);
    const stream = file.startWrite();
    try {
      await writeDraftFile(stream, draft);
      file.finishWrite();
    } catch (error) {
      file.failWrite();
      throw error instanceof Error ? error : new Error('draft write failed');
    }
  }

  static async clearDraft(context: common.UIAbilityContext): Promise<void> {
    try {
      new fileIo.AtomicFile(context.filesDir + DRAFT).delete();
    } catch (error) {
      const coded = error as CodedError;
      if (coded.code !== 13900002) throw error instanceof Error ? error : new Error('draft clear failed');
    }
  }
}
