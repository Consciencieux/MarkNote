import { common } from '@kit.AbilityKit';
import { picker, fileIo, fileShare } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { fileManagerService } from '@kit.FileManagerServiceKit';
import { DocumentInfo } from '../model/Document';
import { FormatRegistry } from '../document/FormatRegistry';
import { TextEncoding, EncodedText } from '../document/TextEncoding';
import { AppText } from '../i18n/AppText';
import { userNotice } from '../document/UserNotice';
import { writeAll } from './FileBytes';

const MAX_BYTES: number = 8 * 1024 * 1024;
const CHUNK_BYTES: number = 64 * 1024;
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

async function fingerprintOf(bytes: Uint8Array): Promise<string> {
  // 空文件也必须有指纹：冲突检查用「指纹为空」表示缺少指纹，
  // 而 MD 的 update 对零长度数据会报 crypto operation error，所以直接返回空输入的摘要。
  if (bytes.length === 0) return EMPTY_DIGEST;
  const md = cryptoFramework.createMd('SHA256');
  const blob: cryptoFramework.DataBlob = { data: bytes };
  await md.update(blob);
  const digest = await md.digest();
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
      await fingerprintOf(await DocumentFiles.readBytes(info.uri)) !== info.fingerprint) {
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
  static async prepare(uri: string, writeRequested: boolean): Promise<FileAccess> {
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

  static async readBytes(uri: string): Promise<Uint8Array> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const size = Number((await fileIo.stat(file.fd)).size);
      if (size > MAX_BYTES) throw userNotice(AppText.text($r('app.string.too_large')));
      const original = new Uint8Array(size);
      let readPosition = 0;
      while (readPosition < size) {
        const length = Math.min(CHUNK_BYTES, size - readPosition);
        const chunk = new ArrayBuffer(length);
        const got = await fileIo.read(file.fd, chunk);
        if (got <= 0) throw userNotice(AppText.text($r('app.string.read_incomplete')));
        original.set(new Uint8Array(chunk, 0, got), readPosition);
        readPosition += got;
      }
      return original;
    } finally {
      await fileIo.close(file);
    }
  }

  static async read(uri: string): Promise<FileContents> {
    let name = '';
    const named = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      name = named.name;
    } catch {
      name = '';
    } finally {
      await fileIo.close(named);
    }
    const original = await DocumentFiles.readBytes(uri);
    const decoded = TextEncoding.decode(original);
    const result = new FileContents();
    result.text = decoded.text;
    result.info.uri = uri;
    // Preserve absence: the service can still use the URI hint or declared type.
    result.info.name = name;
    result.info.newline = decoded.newline;
    result.info.lineEndings = decoded.lineEndings;
    result.info.hasBom = decoded.hasBom;
    result.info.encoding = decoded.encoding;
    result.info.fingerprint = await fingerprintOf(original);
    return result;
  }

  /** Encode once and reject a save that cannot be stored, before any file is opened. */
  static encodedForWrite(info: DocumentInfo, text: string): EncodedText {
    if (info.uri.length === 0) throw userNotice(AppText.text($r('app.string.no_writable_file')));
    if (!info.writable) throw userNotice(AppText.text($r('app.string.no_write_use_save_as')));
    if (info.newline === 'mixed') {
      const parts = text.split('\n');
      if (parts.length !== info.lineEndings.length + 1) {
        throw userNotice(AppText.text($r('app.string.mixed_newlines')));
      }
    }
    const encoded = TextEncoding.encode(text, info);
    if (encoded.bytes.length > MAX_BYTES) throw userNotice(AppText.text($r('app.string.save_too_large')));
    return encoded;
  }

  /** Reject a save that cannot be encoded or would exceed the size limit, before any file is opened. */
  static validateForWrite(info: DocumentInfo, text: string): void {
    DocumentFiles.encodedForWrite(info, text);
  }

  /**
   * Outside providers cannot guarantee atomic replacement. Compare the byte fingerprint
   * taken at open or the last successful save, then verify the bytes written back.
   */
  static async write(info: DocumentInfo, text: string, checkConflict: boolean,
    prepared: EncodedText | null = null): Promise<FileContents> {
    const encoded = prepared === null ? DocumentFiles.encodedForWrite(info, text) : prepared;
    if (checkConflict) {
      if (info.fingerprint.length === 0) {
        throw userNotice(AppText.text($r('app.string.missing_fingerprint')));
      }
      const current = await DocumentFiles.readBytes(info.uri);
      if (await fingerprintOf(current) !== info.fingerprint) {
        throw userNotice(AppText.text($r('app.string.external_change')));
      }
    }
    const bytes = encoded.bytes;
    const expected = await fingerprintOf(bytes);
    const file = await fileIo.open(info.uri, fileIo.OpenMode.READ_WRITE);
    try {
      await writeAll(file.fd, bytes, AppText.text($r('app.string.write_interrupted')));
      await fileIo.truncate(file.fd, bytes.length);
      await fileIo.fsync(file.fd);
    } finally {
      await fileIo.close(file);
    }
    const verified = await DocumentFiles.readBytes(info.uri);
    const actual = await fingerprintOf(verified);
    if (actual !== expected) throw userNotice(AppText.text($r('app.string.verify_failed')));
    const decoded = TextEncoding.decode(verified);
    if (decoded.text !== text) throw userNotice(AppText.text($r('app.string.verify_failed')));
    let name = '';
    const named = await fileIo.open(info.uri, fileIo.OpenMode.READ_ONLY);
    try {
      name = named.name;
    } catch {
      name = '';
    } finally {
      await fileIo.close(named);
    }
    const result = new FileContents();
    result.text = decoded.text;
    result.info.uri = info.uri;
    result.info.name = name.length > 0 ? name : info.name;
    result.info.newline = encoded.newline;
    result.info.lineEndings = encoded.lineEndings;
    result.info.hasBom = decoded.hasBom;
    result.info.encoding = decoded.encoding;
    result.info.fingerprint = actual;
    result.info.formatId = info.formatId;
    result.info.writable = info.writable;
    result.info.persistent = info.persistent;
    return result;
  }
}
