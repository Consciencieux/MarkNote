import { common } from '@kit.AbilityKit';
import { copyInfo, DocumentInfo, Heading, RecoveryData, documentOutline } from '../model/Document';
import { DocumentFiles, FileContents } from '../storage/DocumentFiles';
import { LocalState } from '../storage/LocalState';
import { DocumentFormat, FormatRegistry } from './FormatRegistry';
import { AppText } from '../i18n/AppText';

/** The one open document. DocumentView mirrors these fields into ArkUI state. */
export class DocumentSession {
  info: DocumentInfo = new DocumentInfo();
  source: string = '';
  savedText: string = '';
  editing: boolean = false;
}

export class SaveResult {
  saved: boolean = false;
  stillDirty: boolean = false;
  message: string = '';
}

function fileNameFromUri(uri: string): string {
  const query = uri.indexOf('?');
  const path = query >= 0 ? uri.substring(0, query) : uri;
  const slash = path.lastIndexOf('/');
  const raw = slash >= 0 ? path.substring(slash + 1) : path;
  try {
    return decodeURIComponent(raw);
  } catch {
    return raw;
  }
}

export class DocumentService {
  private static session: DocumentSession = new DocumentSession();

  static current(): DocumentSession {
    return DocumentService.session;
  }

  static formatFor(info: DocumentInfo): DocumentFormat {
    if (info.formatId.length > 0) return FormatRegistry.byId(info.formatId);
    return FormatRegistry.byFilename(info.name);
  }

  /** Only Markdown has a native parser; LaTeX headings arrive from its preview. */
  static nativeHeadingsFor(info: DocumentInfo, source: string): Heading[] {
    if (DocumentService.formatFor(info).id !== 'markdown') return [];
    return documentOutline(source);
  }

  static edit(text: string): void {
    DocumentService.session.source = text;
  }

  static close(): void {
    DocumentService.session.editing = false;
  }

  static startNew(id: string): void {
    const format = FormatRegistry.byId(id);
    const info = new DocumentInfo();
    info.name = FormatRegistry.defaultName(format);
    info.formatId = format.id;
    const session = new DocumentSession();
    session.info = info;
    session.source = format.starter;
    session.savedText = '';
    session.editing = true;
    DocumentService.session = session;
  }

  /**
   * Read a URI without touching the current session until decoding succeeds.
   * strictType rejects system requests whose filename and declared type are both unknown.
   */
  static async openUri(uri: string, declaredType: string, writeRequested: boolean,
    strictType: boolean, beforeAdopt: (() => Promise<boolean>) | null = null): Promise<boolean> {
    const hinted = FormatRegistry.resolve(fileNameFromUri(uri), declaredType, !strictType);
    const access = await DocumentFiles.prepare(uri, writeRequested);
    const loaded = DocumentFiles.read(uri);
    if (loaded.info.name.length === 0) {
      if (hinted === null) throw new Error(AppText.text($r('app.string.unsupported_format')));
      loaded.info.name = FormatRegistry.defaultName(hinted);
    }
    const resolved = FormatRegistry.resolve(loaded.info.name, declaredType, !strictType);
    if (resolved === null) throw new Error(AppText.text($r('app.string.unsupported_format')));
    loaded.info.formatId = resolved.id;
    loaded.info.writable = access.writable;
    loaded.info.persistent = access.persistent;
    if (beforeAdopt !== null && !await beforeAdopt()) return false;
    DocumentService.adopt(loaded);
    return true;
  }

  static adopt(opened: FileContents): void {
    const session = new DocumentSession();
    session.info = opened.info;
    session.source = opened.text;
    session.savedText = opened.text;
    session.editing = true;
    DocumentService.session = session;
  }

  static async restore(draft: RecoveryData, canAdopt: (() => boolean) | null = null): Promise<boolean> {
    const previous = DocumentService.session;
    const previousSource = previous.source;
    const previousEditing = previous.editing;
    const info = new DocumentInfo();
    info.name = draft.name;
    info.uri = draft.uri;
    info.newline = draft.newline;
    info.lineEndings = draft.lineEndings;
    info.encoding = draft.encoding;
    info.hasBom = draft.hasBom;
    info.fingerprint = draft.fingerprint;
    info.formatId = draft.formatId;
    info.writable = false;
    info.persistent = false;
    if (draft.uri.length > 0) {
      try {
        const access = await DocumentFiles.prepare(draft.uri, true);
        const disk = DocumentFiles.read(draft.uri);
        const changed = draft.fingerprint.length > 0
          ? disk.info.fingerprint !== draft.fingerprint
          : disk.text !== draft.savedText;
        info.persistent = access.persistent;
        info.writable = access.writable && !changed;
        if (!changed) info.fingerprint = disk.info.fingerprint;
        if (info.formatId.length === 0) info.formatId = FormatRegistry.byFilename(disk.info.name).id;
      } catch {
        info.writable = false;
        info.persistent = false;
      }
    }
    const session = new DocumentSession();
    session.info = info;
    session.source = draft.text;
    session.savedText = draft.savedText;
    session.editing = true;
    if (DocumentService.session !== previous || previous.source !== previousSource ||
      previous.editing !== previousEditing || (canAdopt !== null && !canAdopt())) return false;
    DocumentService.session = session;
    return true;
  }

  static async save(context: common.UIAbilityContext, asNewFile: boolean): Promise<SaveResult> {
    const result = new SaveResult();
    const session = DocumentService.session;
    if (!session.editing) return result;
    const snapshot = session.source;
    const previous = session.info;
    const readOnly = !asNewFile && previous.uri.length > 0 && !previous.writable;
    let saveAs = asNewFile || previous.uri.length === 0 || !previous.writable;
    let uri = saveAs ? '' : previous.uri;
    if (uri.length === 0) {
      uri = await DocumentFiles.chooseSave(context, previous.name);
      if (uri.length === 0) return result;
      saveAs = true;
    }
    if (DocumentService.session !== session || !session.editing) return result;
    const access = await DocumentFiles.prepare(uri, true);
    if (DocumentService.session !== session || !session.editing) return result;
    if (!access.writable) throw new Error(AppText.text($r('app.string.no_write_permission')));
    const target = copyInfo(previous);
    target.uri = uri;
    target.writable = true;
    target.persistent = access.persistent;
    if (saveAs && target.newline === 'mixed') {
      const parts = snapshot.split('\n');
      if (parts.length !== target.lineEndings.length + 1) {
        target.newline = '\n';
        target.lineEndings = '';
      }
    }
    if (session.source !== session.savedText) {
      const draft = new RecoveryData();
      draft.name = previous.name;
      draft.uri = previous.uri;
      draft.text = session.source;
      draft.savedText = session.savedText;
      draft.newline = previous.newline;
      draft.lineEndings = previous.lineEndings;
      draft.encoding = previous.encoding;
      draft.hasBom = previous.hasBom;
      draft.fingerprint = previous.fingerprint;
      draft.formatId = previous.formatId;
      draft.writable = previous.writable;
      draft.persistent = previous.persistent;
      // Failure here aborts before the provider's file is changed.
      LocalState.writeDraft(context, draft);
    }
    const sameTarget = previous.uri.length > 0 && uri === previous.uri;
    DocumentFiles.write(target, snapshot, !saveAs || sameTarget);
    if (saveAs) {
      const reopened = DocumentFiles.read(uri);
      target.name = reopened.info.name.length > 0 ? reopened.info.name : previous.name;
      target.fingerprint = reopened.info.fingerprint;
      target.writable = true;
      target.persistent = access.persistent;
      const resolved = FormatRegistry.resolve(target.name, '', true);
      if (resolved !== null) target.formatId = resolved.id;
    }
    session.info = target;
    session.savedText = snapshot;
    session.editing = true;
    result.saved = true;
    result.stillDirty = session.source !== snapshot;
    if (result.stillDirty) result.message = AppText.text($r('app.string.saved_dirty'));
    else if (readOnly) result.message = AppText.text($r('app.string.saved_readonly'));
    else result.message = AppText.text($r('app.string.saved'));
    return result;
  }
}
