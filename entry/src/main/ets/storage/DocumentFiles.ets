import { common } from '@kit.AbilityKit';
import { picker, fileIo, fileShare } from '@kit.CoreFileKit';
import { openScratchFile } from './FileBytes';
import { fileManagerService } from '@kit.FileManagerServiceKit';
import { DocumentInfo } from '../model/Document';
import { FormatRegistry } from '../document/FormatRegistry';
import { AppText } from '../i18n/AppText';
import { userNotice } from '../document/UserNotice';
import { fileDigest, inspectDocument, InspectedDocument, writeVerifiedText } from './DocumentStream';

const READ: number = fileShare.OperationMode.READ_MODE;
const WRITE: number = fileShare.OperationMode.WRITE_MODE;
const READ_WRITE: number = READ | WRITE;

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

async function persistedModes(uri: string): Promise<number | null> {
  try {
    const states = await fileShare.checkPersistentPermission([policy(uri, READ), policy(uri, WRITE)]);
    if (states.length !== 2) return null;
    return (states[0] ? READ : 0) | (states[1] ? WRITE : 0);
  } catch {
    return null;
  }
}

async function activate(uri: string, mode: number): Promise<void> {
  if (mode === 0) return;
  try {
    await fileShare.activatePermission([policy(uri, mode)]);
  } catch {
    // A grant can already be active in this process.
  }
}

async function retain(uri: string, mode: number): Promise<boolean> {
  try {
    await fileShare.persistPermission([policy(uri, mode)]);
  } catch {
    return false;
  }
  await activate(uri, mode);
  return true;
}

export class DocumentFiles {
  /** Return the file provider's modification time, or zero when it is unavailable. */
  static async recentModifiedAt(uri: string): Promise<number> {
    try {
      // A URI may be readable through a current grant even without a persisted policy.
      // Activate any stored grant first, then let the file provider decide access.
      await activate(uri, (await persistedModes(uri) ?? 0) & READ);
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

  /** Copy a saved file byte for byte into a picker URI or a private share path. */
  static async writeCopy(sourceUri: string, target: string): Promise<void> {
    if (target.length === 0) throw userNotice(AppText.text($r('app.string.no_writable_file')));
    const expected = await fileFingerprint(sourceUri);
    const input = await fileIo.open(sourceUri, fileIo.OpenMode.READ_ONLY);
    try {
      const output = await fileIo.open(target, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      try {
        const original = await fileIo.stat(input.fd);
        const destination = await fileIo.stat(output.fd);
        if (sourceUri === target || (original.ino > BigInt(0) && original.ino === destination.ino)) {
          throw userNotice(AppText.text($r('app.string.copy_same_file')));
        }
        await fileIo.copyFile(input.fd, output.fd);
        await fileIo.fsync(output.fd);
      } finally {
        await fileIo.close(output);
      }
    } finally {
      await fileIo.close(input);
    }
    if (await fileFingerprint(target) !== expected) {
      throw userNotice(AppText.text($r('app.string.verify_failed')));
    }
  }

  /** Move a stored file to the recycle bin after checking write access and current bytes. */
  static async deleteStored(uri: string): Promise<void> {
    const access = await DocumentFiles.prepare(uri, true);
    if (!access.writable) throw userNotice(AppText.text($r('app.string.no_delete_permission')));
    const info = new DocumentInfo();
    info.uri = uri;
    info.writable = true;
    info.fingerprint = await fileFingerprint(uri);
    await DocumentFiles.moveToTrash(info);
  }
  /**
   * A persisted picker grant stays inactive across launches until activatePermission.
   * Activate both stored modes before canOpen. Opening first makes a still-valid
   * recent file look expired, and the grant is never activated.
   */
  static async prepare(uri: string, writeRequested: boolean, persist: boolean = true): Promise<FileAccess> {
    const access = new FileAccess();
    if (uri.length === 0) return access;
    let stored = await persistedModes(uri);
    if (stored === null) stored = await persistedModes(uri);
    await activate(uri, stored ?? 0);
    const writable = writeRequested && await canOpen(uri, fileIo.OpenMode.READ_WRITE);
    const readable = writable || await canOpen(uri, fileIo.OpenMode.READ_ONLY);
    if (!readable) throw userNotice(AppText.text($r('app.string.auth_expired')));
    // A failed query leaves the old grants unknown. Use the current grant without persisting it.
    if (persist && stored !== null) {
      const missing = (writable ? READ_WRITE : READ) & ~stored;
      if (missing !== 0 && await retain(uri, missing)) {
        access.newMode = missing;
        stored |= missing;
      } else if (missing === READ_WRITE && await retain(uri, READ)) {
        access.newMode = READ;
        stored |= READ;
      }
    }
    access.writable = writable;
    access.persistent = ((stored ?? 0) & READ) !== 0;
    return access;
  }

  static async release(uri: string): Promise<void> {
    if (uri.length === 0) return;
    const modes: number[] = [READ_WRITE, READ];
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

  static async read(uri: string, encoding: string = ''): Promise<FileContents> {
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
      }, null, encoding);
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
