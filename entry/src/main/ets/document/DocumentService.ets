import { common } from '@kit.AbilityKit';
import { copyInfo, DocumentInfo, DraftSnapshot, Heading, RecoveryData, documentOutline } from '../model/Document';
import { DocumentFiles, FileContents } from '../storage/DocumentFiles';
import { DraftCoordinator } from './DraftCoordinator';
import { DocumentFormat, FormatRegistry } from './FormatRegistry';
import { AppText } from '../i18n/AppText';
import { userNotice } from './UserNotice';

/** The one open document. DocumentView mirrors these fields into ArkUI state. */
export class DocumentSession {
  id: number = 0;
  revision: number = 0;
  /** 'idle', 'save', or 'delete'. A second file operation waits until this returns to idle. */
  fileOperation: string = 'idle';
  info: DocumentInfo = new DocumentInfo();
  source: string = '';
  savedText: string = '';
  editing: boolean = false;
  writeUncertain: boolean = false;
  pendingWriteText: string = '';
  pendingWriteUri: string = '';

  constructor(id: number) {
    this.id = id;
  }
}

export class SaveResult {
  sessionId: number = 0;
  saved: boolean = false;
  stillDirty: boolean = false;
  message: string = '';
}

export class DeleteResult {
  sessionId: number = 0;
  deleted: boolean = false;
  retainedEdits: boolean = false;
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
  private static nextId: number = 1;
  private static session: DocumentSession = new DocumentSession(DocumentService.allocateId());
  private static drafts: DraftCoordinator | null = null;
  private static recoveryError: (sessionId: number, error: Error) => void =
    (_sessionId: number, _error: Error): void => {};

  private static allocateId(): number {
    const id = DocumentService.nextId;
    DocumentService.nextId++;
    return id;
  }

  static current(): DocumentSession {
    return DocumentService.session;
  }

  static initializeRecovery(context: common.UIAbilityContext): void {
    if (DocumentService.drafts !== null) return;
    const coordinator = new DraftCoordinator(context);
    coordinator.onError = (sessionId: number, error: Error): void => {
      DocumentService.recoveryError(sessionId, error);
    };
    coordinator.activate(DocumentService.session.id);
    DocumentService.drafts = coordinator;
  }

  static bindRecoveryError(handler: (sessionId: number, error: Error) => void): void {
    DocumentService.recoveryError = handler;
  }

  static unbindRecoveryError(): void {
    DocumentService.recoveryError = (_sessionId: number, _error: Error): void => {};
  }

  static activateSession(session: DocumentSession): void {
    if (DocumentService.drafts !== null) DocumentService.drafts.activate(session.id);
  }

  static flushRecovery(): Promise<void> {
    if (DocumentService.drafts === null) return Promise.resolve();
    return DocumentService.drafts.flush();
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

  /** Returns false when the text did not change, so callers can skip analysis and history. */
  static edit(text: string): boolean {
    const session = DocumentService.session;
    if (!session.editing || session.source === text) return false;
    session.source = text;
    session.revision++;
    if (session.source === session.savedText && !session.writeUncertain) DocumentService.releaseDraft(session);
    else DocumentService.scheduleDraft(session);
    return true;
  }

  static close(): void {
    DocumentService.session.editing = false;
  }

  /** Drop the previous recovery file before publishing another session. */
  static async startNew(id: string): Promise<boolean> {
    if (DocumentService.session.fileOperation !== 'idle') return false;
    if (!await DocumentService.abandonCurrentRecovery()) return false;
    if (DocumentService.session.fileOperation !== 'idle') return false;
    const format = FormatRegistry.byId(id);
    const info = new DocumentInfo();
    info.name = FormatRegistry.defaultName(format);
    info.formatId = format.id;
    const session = new DocumentSession(DocumentService.allocateId());
    session.info = info;
    session.source = format.starter;
    session.savedText = '';
    session.editing = true;
    DocumentService.session = session;
    DocumentService.activateSession(session);
    return true;
  }

  /**
   * Read a URI without touching the current session until decoding succeeds.
   * strictType rejects system requests whose filename and declared type are both unknown.
   */
  static async openUri(uri: string, declaredType: string, writeRequested: boolean,
    strictType: boolean, beforeAdopt: (() => Promise<boolean>) | null = null): Promise<boolean> {
    if (DocumentService.session.fileOperation !== 'idle') return false;
    const hinted = FormatRegistry.resolve(fileNameFromUri(uri), declaredType, !strictType);
    const access = await DocumentFiles.prepare(uri, writeRequested);
    const loaded = await DocumentFiles.read(uri);
    if (loaded.info.name.length === 0) {
      if (hinted === null) throw userNotice(AppText.text($r('app.string.unsupported_format')));
      loaded.info.name = FormatRegistry.defaultName(hinted);
    }
    const resolved = FormatRegistry.resolve(loaded.info.name, declaredType, !strictType);
    if (resolved === null) throw userNotice(AppText.text($r('app.string.unsupported_format')));
    loaded.info.formatId = resolved.id;
    loaded.info.writable = access.writable;
    loaded.info.persistent = access.persistent;
    if (DocumentService.session.fileOperation !== 'idle') return false;
    if (beforeAdopt !== null && !await beforeAdopt()) return false;
    if (DocumentService.session.fileOperation !== 'idle') return false;
    return DocumentService.adopt(loaded);
  }

  static async adopt(opened: FileContents): Promise<boolean> {
    if (DocumentService.session.fileOperation !== 'idle') return false;
    if (!await DocumentService.abandonCurrentRecovery()) return false;
    if (DocumentService.session.fileOperation !== 'idle') return false;
    const session = new DocumentSession(DocumentService.allocateId());
    session.info = opened.info;
    session.source = opened.text;
    session.savedText = opened.text;
    session.editing = true;
    DocumentService.session = session;
    DocumentService.activateSession(session);
    return true;
  }

  static async restore(draft: RecoveryData, canAdopt: (() => boolean) | null = null): Promise<boolean> {
    if (DocumentService.session.fileOperation !== 'idle') return false;
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
        const disk = await DocumentFiles.read(draft.uri);
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
    const session = new DocumentSession(DocumentService.allocateId());
    session.info = info;
    session.source = draft.text;
    session.savedText = draft.savedText;
    session.writeUncertain = draft.writeUncertain === true;
    session.pendingWriteText = typeof draft.pendingWriteText === 'string' ? draft.pendingWriteText : '';
    session.pendingWriteUri = typeof draft.pendingWriteUri === 'string' ? draft.pendingWriteUri : '';
    session.editing = true;
    if (DocumentService.session !== previous || previous.source !== previousSource ||
      previous.editing !== previousEditing || DocumentService.session.fileOperation !== 'idle' ||
      (canAdopt !== null && !canAdopt())) return false;
    DocumentService.session = session;
    DocumentService.activateSession(session);
    DocumentService.scheduleDraft(session);
    return true;
  }

  static async save(context: common.UIAbilityContext, asNewFile: boolean): Promise<SaveResult> {
    const result = new SaveResult();
    const session = DocumentService.session;
    result.sessionId = session.id;
    if (!session.editing || session.fileOperation !== 'idle') return result;
    session.fileOperation = 'save';
    const snapshot = session.source;
    const baseline = session.savedText;
    const previous = session.info;
    const readOnly = !asNewFile && previous.uri.length > 0 && !previous.writable;
    if (!asNewFile && previous.uri.length > 0 && previous.writable && snapshot === baseline && !session.writeUncertain) {
      session.fileOperation = 'idle';
      result.saved = true;
      result.message = AppText.text($r('app.string.saved'));
      return result;
    }
    let writeStarted = false;
    let checkpointPrepared = false;
    const oldUncertain = session.writeUncertain;
    const oldPendingText = session.pendingWriteText;
    const oldPendingUri = session.pendingWriteUri;
    try {
      let saveAs = asNewFile || previous.uri.length === 0 || !previous.writable;
      let uri = saveAs ? '' : previous.uri;
      if (uri.length === 0) {
        uri = await DocumentFiles.chooseSave(context, previous.name);
        if (uri.length === 0 || DocumentService.session !== session || !session.editing) return result;
        saveAs = true;
      }
      if (DocumentService.session !== session || !session.editing) return result;
      const access = await DocumentFiles.prepare(uri, true);
      if (DocumentService.session !== session || !session.editing) return result;
      if (!access.writable) throw userNotice(AppText.text($r('app.string.no_write_permission')));
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
      const encoded = DocumentFiles.encodedForWrite(target, snapshot);
      session.writeUncertain = true;
      session.pendingWriteText = snapshot;
      session.pendingWriteUri = uri;
      checkpointPrepared = true;
      await DocumentService.checkpointRecovery(session, baseline, previous);
      if (DocumentService.session !== session || !session.editing) return result;
      const sameTarget = previous.uri.length > 0 && uri === previous.uri;
      const verified = await DocumentFiles.write(target, snapshot, !saveAs || sameTarget, encoded,
        (): void => { writeStarted = true; });
      if (DocumentService.session !== session || !session.editing || session.fileOperation !== 'save') return result;
      target.name = verified.info.name.length > 0 ? verified.info.name : previous.name;
      target.fingerprint = verified.info.fingerprint;
      target.newline = verified.info.newline;
      target.lineEndings = verified.info.lineEndings;
      target.hasBom = verified.info.hasBom;
      target.encoding = verified.info.encoding;
      target.writable = true;
      target.persistent = access.persistent;
      const resolved = FormatRegistry.resolve(target.name, '', true);
      if (resolved !== null) target.formatId = resolved.id;
      session.info = target;
      session.savedText = snapshot;
      session.writeUncertain = false;
      session.pendingWriteText = '';
      session.pendingWriteUri = '';
      result.saved = true;
      result.stillDirty = session.source !== snapshot;
      result.sessionId = session.id;
      if (result.stillDirty) {
        DocumentService.scheduleDraft(session);
        result.message = AppText.text($r('app.string.saved_dirty'));
      } else {
        try {
          const cleared = await DocumentService.clearRecovery(session, 'saved');
          if (!cleared) DocumentService.scheduleDraft(session);
        } catch (error) {
          DocumentService.reportRecovery(session.id, error);
        }
        if (readOnly) result.message = AppText.text($r('app.string.saved_readonly'));
        else result.message = AppText.text($r('app.string.saved'));
      }
      return result;
    } catch (error) {
      if (checkpointPrepared && !writeStarted) {
        session.writeUncertain = oldUncertain;
        session.pendingWriteText = oldPendingText;
        session.pendingWriteUri = oldPendingUri;
      }
      if (checkpointPrepared && DocumentService.session === session && session.editing) {
        if (writeStarted) {
          try {
            await DocumentService.checkpointRecovery(session, session.savedText, session.info);
          } catch (recoveryError) {
            DocumentService.reportRecovery(session.id, recoveryError);
            DocumentService.scheduleDraft(session);
          }
        } else if (session.source !== session.savedText || session.writeUncertain) DocumentService.scheduleDraft(session);
        else DocumentService.releaseDraft(session);
      }
      throw error instanceof Error ? error : new Error('save failed');
    } finally {
      if (session.fileOperation === 'save') session.fileOperation = 'idle';
    }
  }

  static async moveToTrash(): Promise<DeleteResult> {
    const result = new DeleteResult();
    const session = DocumentService.session;
    result.sessionId = session.id;
    if (!session.editing || session.fileOperation !== 'idle') return result;
    const sourceBefore = session.source;
    const uri = session.info.uri;
    session.fileOperation = 'delete';
    try {
      await DocumentFiles.moveToTrash(session.info);
      if (DocumentService.session !== session || session.info.uri !== uri) return result;
      result.deleted = true;
      if (session.source !== sourceBefore) {
        result.retainedEdits = true;
        session.info.uri = '';
        session.info.writable = false;
        session.info.persistent = false;
        session.info.fingerprint = '';
        session.savedText = '';
        DocumentService.scheduleDraft(session);
      } else {
        try {
          await DocumentService.clearRecovery(session, 'discarded');
        } catch (error) {
          DocumentService.reportRecovery(session.id, error);
        }
        session.editing = false;
      }
      return result;
    } finally {
      if (session.fileOperation === 'delete') session.fileOperation = 'idle';
    }
  }

  static async clearRecovery(owner: DocumentSession, _reason: string): Promise<boolean> {
    if (DocumentService.drafts === null) return true;
    return DocumentService.drafts.clear(DocumentService.makeSnapshot(owner));
  }

  private static reportRecovery(sessionId: number, error: Object): void {
    const wrapped = error instanceof Error ? error : new Error('draft failed');
    DocumentService.recoveryError(sessionId, wrapped);
  }

  /** Clear a recovery file before another document takes its place. A busy or newer edit keeps the current session. */
  private static async abandonCurrentRecovery(): Promise<boolean> {
    const owner = DocumentService.session;
    if (!owner.editing) return true;
    const source = owner.source;
    const cleared = await DocumentService.clearRecovery(owner, 'discarded');
    if (DocumentService.session !== owner || owner.fileOperation !== 'idle' || owner.source !== source) return false;
    return cleared;
  }

  private static releaseDraft(session: DocumentSession): void {
    if (DocumentService.drafts === null) return;
    DocumentService.drafts.clear(DocumentService.makeSnapshot(session)).catch((error: Object): void => {
      DocumentService.reportRecovery(session.id, error);
    });
  }

  private static scheduleDraft(session: DocumentSession): void {
    if (DocumentService.drafts === null || !session.editing) return;
    if (session.source === session.savedText && !session.writeUncertain) return;
    DocumentService.drafts.schedule(DocumentService.makeSnapshot(session));
  }

  private static async checkpointRecovery(owner: DocumentSession, savedBaseline: string, info: DocumentInfo): Promise<void> {
    if (DocumentService.drafts === null) throw new Error('recovery unavailable');
    const shot = DocumentService.makeSnapshot(owner);
    shot.data.text = owner.source;
    shot.data.savedText = savedBaseline;
    shot.data.name = info.name;
    shot.data.uri = info.uri;
    shot.data.newline = info.newline;
    shot.data.lineEndings = info.lineEndings;
    shot.data.encoding = info.encoding;
    shot.data.hasBom = info.hasBom;
    shot.data.fingerprint = info.fingerprint;
    shot.data.formatId = info.formatId;
    shot.data.writable = info.writable;
    shot.data.persistent = info.persistent;
    await DocumentService.drafts.checkpoint(shot);
  }

  private static makeSnapshot(session: DocumentSession): DraftSnapshot {
    const data = new RecoveryData();
    data.name = session.info.name;
    data.uri = session.info.uri;
    data.text = session.source;
    data.savedText = session.savedText;
    data.newline = session.info.newline;
    data.lineEndings = session.info.lineEndings;
    data.encoding = session.info.encoding;
    data.hasBom = session.info.hasBom;
    data.fingerprint = session.info.fingerprint;
    data.formatId = session.info.formatId;
    data.writable = session.info.writable;
    data.persistent = session.info.persistent;
    data.writeUncertain = session.writeUncertain;
    data.pendingWriteText = session.pendingWriteText;
    data.pendingWriteUri = session.pendingWriteUri;
    const shot = new DraftSnapshot();
    shot.sessionId = session.id;
    shot.revision = session.revision;
    shot.data = data;
    return shot;
  }
}
