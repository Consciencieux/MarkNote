import { common } from '@kit.AbilityKit';
import { picker, fileIo, fileShare } from '@kit.CoreFileKit';
import { openScratchFile } from './FileBytes';
import { fileManagerService } from '@kit.FileManagerServiceKit';
import { DocumentInfo } from '../model/Document';
import { FormatRegistry } from '../document/FormatRegistry';
import { AppText } from '../i18n/AppText';
import { userNotice } from '../document/UserNotice';
import { fileDigest, inspectDocument, InspectedDocument, writeVerifiedText } from './DocumentStream';

const READ_WRITE: number = fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE;

export class FileContents {
  info: DocumentInfo = new DocumentInfo();
  text: string = '';
}

/** What the system actually granted for one URI. Writable is the result of opening, not of the URI string. */
export class FileAccess {
  writable: boolean = false;
  persistent: boolean = false;
  newMode: number = 0;
}

export class PreparedWrite {
  file: fileIo.File;
  verified: InspectedDocument;

  constructor(file: fileIo.File, verified: InspectedDocument) {
    this.file = file;
    this.verified = verified;
  }

  async close(): Promise<void> {
    await fileIo.close(this.file);
  }
}

async function fileFingerprint(uri: string): Promise<string> {
  const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
  try {
    return await fileDigest(file.fd);
  } finally {
    await fileIo.close(file);
  }
}

function fileName(file: fileIo.File): string {
  try {
    return file.name;
  } catch {
    return '';
  }
}

function policy(uri: string, mode: number): fileShare.PolicyInfo {
  return { uri: uri, operationMode: mode };
}

async function canOpen(uri: string, mode: number): Promise<boolean> {
  try {
    const file = await fileIo.open(uri, mode);
    await fileIo.close(file);
    return true;
  } catch {
    return false;
  }
}

async function persisted(uri: string, mode: number): Promise<boolean> {
  const item = policy(uri, mode);
  try {
    const states = await fileShare.checkPersistentPermission([item]);
    if (states.length === 0 || !states[0]) return false;
    try {
      await fileShare.activatePermission([item]);
    } catch {
      // A grant can already be active in this process.
    }
    return true;
  } catch {
    return false;
  }
}

async function retain(uri: string, mode: number): Promise<boolean> {
  if (await persisted(uri, mode)) return true;
  const item = policy(uri, mode);
  try {
    await fileShare.persistPermission([item]);
  } catch {
    return false;
  }
  try {
    await fileShare.activatePermission([item]);
  } catch {
    // Persisted for the next launch even if this process can already open the file.
  }
  return true;
}

export class DocumentFiles {
  /** Return the file provider's modification time, or zero when it is unavailable. */
  static async recentModifiedAt(uri: string): Promise<number> {
    try {
      // A URI may be readable through a current grant even without a persisted policy.
      // Activate any stored grant first, then let the file provider decide access.
      await persisted(uri, READ_WRITE) || await persisted(uri, fileShare.OperationMode.READ_MODE);
      const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      try {
        const info = await fileIo.stat(file.fd);
        return info.mtime > 0 ? info.mtime : 0;
      } finally {
        await fileIo.close(file);
      }
    } catch {
      return 0;
    }
  }
  /** Move the opened version to the system recycle bin; never fall back to permanent deletion. */
  static async moveToTrash(info: DocumentInfo): Promise<void> {
    if (info.uri.length === 0) throw userNotice(AppText.text($r('app.string.not_saved_file')));
    if (!info.writable) throw userNotice(AppText.text($r('app.string.no_delete_permission')));
    if (info.fingerprint.length === 0 ||
      await fileFingerprint(info.uri) !== info.fingerprint) {
      throw userNotice(AppText.text($r('app.string.delete_conflict')));
    }
    // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/filemanagerservice-arkts-filemanagerservice
    await fileManagerService.deleteToTrash(info.uri);
  }
  /**
   * A persisted picker grant stays inactive across launches until activatePermission.
   * Activate both stored modes before canOpen. Opening first makes a still-valid
   * recent file look expired, and the grant is never activated.
   */
  static async prepare(uri: string, writeRequested: boolean, persist: boolean = true): Promise<FileAccess> {
    const access = new FileAccess();
    if (uri.length === 0) return access;
    // Must run before canOpen. A restart leaves the persisted grant inactive.
    const persistedWrite = await persisted(uri, READ_WRITE);
    const persistedRead = persistedWrite || await persisted(uri, fileShare.OperationMode.READ_MODE);
    const writable = writeRequested && await canOpen(uri, fileIo.OpenMode.READ_WRITE);
    const readable = writable || await canOpen(uri, fileIo.OpenMode.READ_ONLY);
    if (!readable) throw userNotice(AppText.text($r('app.string.auth_expired')));
    const mode = writable ? READ_WRITE : fileShare.OperationMode.READ_MODE;
    let persistent = writable ? persistedWrite : persistedRead;
    if (persist && !persistent) {
      persistent = await retain(uri, mode);
      // Revoke only the newly added write grant when read access already existed.
      if (persistent) {
        access.newMode = persistedRead ? fileShare.OperationMode.WRITE_MODE : mode;
      }
    }
    if (persist && !persistent && writable) {
      persistent = await retain(uri, fileShare.OperationMode.READ_MODE);
      if (persistent && !persistedRead) access.newMode = fileShare.OperationMode.READ_MODE;
    }
    access.writable = writable;
    access.persistent = persistent;
    return access;
  }

  static async release(uri: string): Promise<void> {
    if (uri.length === 0) return;
    const modes: number[] = [READ_WRITE, fileShare.OperationMode.READ_MODE];
    for (let index = 0; index < modes.length; index++) {
      try {
        await fileShare.revokePermission([policy(uri, modes[index])]);
      } catch {
        // The persisted grant may already have been removed.
      }
    }
  }

  static async releaseNew(uri: string, access: FileAccess): Promise<void> {
    if (access.newMode === 0) return;
    try {
      await fileShare.revokePermission([policy(uri, access.newMode)]);
    } catch {
      // The grant may already have been removed by the provider.
    }
  }

  static async chooseOpen(context: common.UIAbilityContext): Promise<string> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = FormatRegistry.openFilters();
    const uris = await new picker.DocumentViewPicker(context).select(options);
    return uris.length === 0 ? '' : uris[0];
  }

  static async chooseSave(context: common.UIAbilityContext, filename: string): Promise<string> {
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [filename];
    options.fileSuffixChoices = FormatRegistry.saveChoices(filename);
    const uris = await new picker.DocumentViewPicker(context).save(options);
    return uris.length === 0 ? '' : uris[0];
  }

  static async read(uri: string): Promise<FileContents> {
    let file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    let inspected: InspectedDocument;
    let name = '';
    try {
      inspected = await inspectDocument(file.fd, async (): Promise<number> => {
        // A provider can expose a non-seekable descriptor. Each fallback starts at byte zero.
        const previous = file;
        file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
        await fileIo.close(previous);
        return file.fd;
      }, null);
      name = fileName(file);
    } finally {
      await fileIo.close(file);
    }
    const decoded = inspected.decoded;
    const result = new FileContents();
    result.text = decoded.text;
    result.info.uri = uri;
    // Preserve absence: the service can still use the URI hint or declared type.
    result.info.name = name;
    result.info.newline = decoded.newline;
    result.info.lineEndings = decoded.lineEndings;
    result.info.hasBom = decoded.hasBom;
    result.info.encoding = decoded.encoding;
    result.info.fingerprint = inspected.fingerprint;
    return result;
  }

  static async prepareWrite(cacheDir: string, info: DocumentInfo, text: string): Promise<PreparedWrite> {
    if (info.uri.length === 0) throw userNotice(AppText.text($r('app.string.no_writable_file')));
    if (!info.writable) throw userNotice(AppText.text($r('app.string.no_write_use_save_as')));
    const file = await openScratchFile(cacheDir);
    try {
      const verified = await writeVerifiedText(file.fd, text, info, AppText.text($r('app.string.write_interrupted')));
      return new PreparedWrite(file, verified);
    } catch (error) {
      await fileIo.close(file);
      throw error as Error;
    }
  }

  /** Update the target metadata only after the verified snapshot has been copied and checked. */
  static async write(info: DocumentInfo, checkConflict: boolean,
    prepared: PreparedWrite, onWriteStart: () => void): Promise<void> {
    if (checkConflict) {
      if (info.fingerprint.length === 0) {
        throw userNotice(AppText.text($r('app.string.missing_fingerprint')));
      }
      if (await fileFingerprint(info.uri) !== info.fingerprint) {
        throw userNotice(AppText.text($r('app.string.external_change')));
      }
    }
    const file = await fileIo.open(info.uri, fileIo.OpenMode.READ_WRITE);
    let name = '';
    try {
      onWriteStart();
      fileIo.lseek(prepared.file.fd, 0);
      await fileIo.copyFile(prepared.file.fd, file.fd);
      await fileIo.fsync(file.fd);
      name = fileName(file);
    } finally {
      await fileIo.close(file);
    }
    // The encoder already checked the exact bytes round-trip to the original text.
    const actual = await fileFingerprint(info.uri);
    if (actual !== prepared.verified.fingerprint) throw userNotice(AppText.text($r('app.string.verify_failed')));
    if (name.length > 0) info.name = name;
    info.hasBom = prepared.verified.decoded.hasBom;
    info.encoding = prepared.verified.decoded.encoding;
    info.fingerprint = actual;
  }
}
