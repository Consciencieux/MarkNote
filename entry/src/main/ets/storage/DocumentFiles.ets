import { common } from '@kit.AbilityKit';
import { picker, fileIo, fileShare } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { fileManagerService } from '@kit.FileManagerServiceKit';
import { DocumentInfo } from '../model/Document';
import { FormatRegistry } from '../document/FormatRegistry';
import { TextEncoding } from '../document/TextEncoding';
import { AppText } from '../i18n/AppText';

const MAX_BYTES: number = 8 * 1024 * 1024;
const READ_WRITE: number = fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE;

export class FileContents {
  info: DocumentInfo = new DocumentInfo();
  text: string = '';
}

/** What the system actually granted for one URI. Writable is the result of opening, not of the URI string. */
export class FileAccess {
  writable: boolean = false;
  persistent: boolean = false;
}

/** SHA-256 of empty input. Frames MD does not accept a zero-length update, so it is a constant. */
const EMPTY_DIGEST: string = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

function fingerprintOf(bytes: Uint8Array): string {
  // 空文件也必须有指纹：冲突检查用「指纹为空」表示缺少指纹，
  // 而 MD 的 updateSync 对零长度数据会报 crypto operation error，所以直接返回空输入的摘要。
  if (bytes.length === 0) return EMPTY_DIGEST;
  const md = cryptoFramework.createMd('SHA256');
  const blob: cryptoFramework.DataBlob = { data: bytes };
  md.updateSync(blob);
  const digest = md.digestSync();
  const data = digest.data;
  let hex = '';
  for (let index = 0; index < data.length; index++) {
    const value = data[index];
    hex += (value < 16 ? '0' : '') + value.toString(16);
  }
  return hex;
}

function policy(uri: string, mode: number): fileShare.PolicyInfo {
  return { uri: uri, operationMode: mode };
}

function canOpen(uri: string, mode: number): boolean {
  try {
    const file = fileIo.openSync(uri, mode);
    fileIo.closeSync(file);
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
    if (info.uri.length === 0) throw new Error(AppText.text($r('app.string.not_saved_file')));
    if (!info.writable) throw new Error(AppText.text($r('app.string.no_delete_permission')));
    if (info.fingerprint.length === 0 || fingerprintOf(DocumentFiles.readBytes(info.uri)) !== info.fingerprint) {
      throw new Error(AppText.text($r('app.string.delete_conflict')));
    }
    // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/filemanagerservice-arkts-filemanagerservice
    await fileManagerService.deleteToTrash(info.uri);
  }
  /**
   * A persisted picker grant stays inactive across launches until activatePermission.
   * Activate both stored modes before canOpen. Opening first makes a still-valid
   * recent file look expired, and the grant is never activated.
   */
  static async prepare(uri: string, writeRequested: boolean): Promise<FileAccess> {
    const access = new FileAccess();
    if (uri.length === 0) return access;
    // Must run before canOpen. A restart leaves the persisted grant inactive.
    const persistedWrite = await persisted(uri, READ_WRITE);
    const persistedRead = persistedWrite || await persisted(uri, fileShare.OperationMode.READ_MODE);
    const writable = writeRequested && canOpen(uri, fileIo.OpenMode.READ_WRITE);
    const readable = writable || canOpen(uri, fileIo.OpenMode.READ_ONLY);
    if (!readable) throw new Error(AppText.text($r('app.string.auth_expired')));
    const mode = writable ? READ_WRITE : fileShare.OperationMode.READ_MODE;
    let persistent = writable ? persistedWrite : persistedRead;
    if (!persistent) persistent = await retain(uri, mode);
    if (!persistent && writable) persistent = await retain(uri, fileShare.OperationMode.READ_MODE);
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

  static readBytes(uri: string): Uint8Array {
    const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const size = Number(fileIo.statSync(file.fd).size);
      if (size > MAX_BYTES) throw new Error(AppText.text($r('app.string.too_large')));
      const original = new Uint8Array(size);
      let readPosition = 0;
      while (readPosition < size) {
        const chunk = new ArrayBuffer(Math.min(64 * 1024, size - readPosition));
        const length = fileIo.readSync(file.fd, chunk);
        if (length <= 0) throw new Error(AppText.text($r('app.string.read_incomplete')));
        original.set(new Uint8Array(chunk, 0, length), readPosition);
        readPosition += length;
      }
      return original;
    } finally {
      fileIo.closeSync(file);
    }
  }

  static read(uri: string): FileContents {
    let name = '';
    const named = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      name = named.name;
    } catch {
      name = '';
    } finally {
      fileIo.closeSync(named);
    }
    const original = DocumentFiles.readBytes(uri);
    const decoded = TextEncoding.decode(original);
    const result = new FileContents();
    result.text = decoded.text;
    result.info.uri = uri;
    result.info.name = name.length > 0 ? name : FormatRegistry.defaultName(FormatRegistry.byId('plain'));
    result.info.newline = decoded.newline;
    result.info.lineEndings = decoded.lineEndings;
    result.info.hasBom = decoded.hasBom;
    result.info.encoding = decoded.encoding;
    result.info.fingerprint = fingerprintOf(original);
    return result;
  }

  /**
   * Outside providers cannot guarantee atomic replacement. Compare the byte fingerprint
   * taken at open or the last successful save, then verify the bytes written back.
   */
  static write(info: DocumentInfo, text: string, checkConflict: boolean): void {
    if (info.uri.length === 0) throw new Error(AppText.text($r('app.string.no_writable_file')));
    if (!info.writable) throw new Error(AppText.text($r('app.string.no_write_use_save_as')));
    if (checkConflict) {
      if (info.fingerprint.length === 0) {
        throw new Error(AppText.text($r('app.string.missing_fingerprint')));
      }
      const current = DocumentFiles.readBytes(info.uri);
      if (fingerprintOf(current) !== info.fingerprint) {
        throw new Error(AppText.text($r('app.string.external_change')));
      }
    }
    if (info.newline === 'mixed') {
      const parts = text.split('\n');
      if (parts.length !== info.lineEndings.length + 1) {
        throw new Error(AppText.text($r('app.string.mixed_newlines')));
      }
    }
    const encoded = TextEncoding.encode(text, info);
    if (encoded.bytes.length > MAX_BYTES) {
      throw new Error(AppText.text($r('app.string.save_too_large')));
    }
    info.newline = encoded.newline;
    info.lineEndings = encoded.lineEndings;
    const bytes = encoded.bytes;
    const file = fileIo.openSync(info.uri, fileIo.OpenMode.READ_WRITE);
    try {
      let offset = 0;
      while (offset < bytes.length) {
        const remaining = bytes.slice(offset);
        const written = fileIo.writeSync(file.fd, remaining.buffer);
        if (written <= 0) throw new Error(AppText.text($r('app.string.write_interrupted')));
        offset += written;
      }
      fileIo.truncateSync(file.fd, bytes.length);
      fileIo.fsyncSync(file.fd);
    } finally {
      fileIo.closeSync(file);
    }
    const verified = DocumentFiles.readBytes(info.uri);
    if (fingerprintOf(verified) !== fingerprintOf(bytes)) {
      throw new Error(AppText.text($r('app.string.verify_failed')));
    }
    const decoded = TextEncoding.decode(verified);
    if (decoded.text !== text) throw new Error(AppText.text($r('app.string.verify_failed')));
    info.fingerprint = fingerprintOf(verified);
    info.hasBom = decoded.hasBom;
    info.encoding = decoded.encoding;
  }
}
