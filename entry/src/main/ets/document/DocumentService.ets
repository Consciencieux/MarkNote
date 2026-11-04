import { common } from '@kit.AbilityKit';
import { copyInfo, DocumentInfo, Heading, RecoveryData, documentOutline } from '../model/Document';
import { DocumentFiles, FileContents } from '../storage/DocumentFiles';
import { DocumentFormat, FormatRegistry } from './FormatRegistry';

/** The one open document. Index mirrors these fields into ArkUI state. */
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

  static headingsFor(info: DocumentInfo, source: string): Heading[] {
    if (!DocumentService.formatFor(info).outline) return [];
    return documentOutline(source);
  }

  static isDirty(): boolean {
    const session = DocumentService.session;
    return session.editing && session.source !== session.savedText;
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
    info.name = format.defaultFilename;
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
    strictType: boolean): Promise<void> {
    const hinted = FormatRegistry.resolve(fileNameFromUri(uri), declaredType, !strictType);
    if (hinted === null) throw new Error('这个文件不是 Marknote 支持的文稿格式');
    const access = await DocumentFiles.prepare(uri, writeRequested);
    const loaded = DocumentFiles.read(uri);
    if (loaded.info.name.length === 0) loaded.info.name = hinted.defaultFilename;
    const resolved = FormatRegistry.resolve(loaded.info.name, declaredType, !strictType);
    if (resolved === null) throw new Error('这个文件不是 Marknote 支持的文稿格式');
    loaded.info.formatId = resolved.id;
    loaded.info.writable = access.writable;
    loaded.info.persistent = access.persistent;
    DocumentService.adopt(loaded);
  }

  static adopt(opened: FileContents): void {
    const session = new DocumentSession();
    session.info = opened.info;
    session.source = opened.text;
    session.savedText = opened.text;
    session.editing = true;
    DocumentService.session = session;
  }

  static async restore(draft: RecoveryData): Promise<void> {
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
    DocumentService.session = session;
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
    const access = await DocumentFiles.prepare(uri, true);
    if (!access.writable) throw new Error('没有获得写入权限，请改用“另存为”');
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
    DocumentFiles.write(target, snapshot, !saveAs);
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
    if (result.stillDirty) result.message = '已保存操作开始时的版本，仍有未保存修改';
    else if (readOnly) result.message = '当前文件只读，已另存为';
    else result.message = '已保存';
    return result;
  }
}
