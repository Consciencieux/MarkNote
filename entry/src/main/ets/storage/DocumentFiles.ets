import { common } from '@kit.AbilityKit';
import { picker, fileIo, fileShare } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { DocumentInfo } from '../model/Document';
import { FormatRegistry } from '../document/FormatRegistry';
import { TextEncoding } from '../document/TextEncoding';

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

function fingerprintOf(bytes: Uint8Array): string {
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
    if (!readable) throw new Error('原文件授权可能已经失效，请使用“打开”重新选取');
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
      if (size > MAX_BYTES) throw new Error('暂时只支持不超过 8 MiB 的文稿');
      const original = new Uint8Array(size);
      let readPosition = 0;
      while (readPosition < size) {
        const chunk = new ArrayBuffer(Math.min(64 * 1024, size - readPosition));
        const length = fileIo.readSync(file.fd, chunk);
        if (length <= 0) throw new Error('读取不完整，请重试');
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
    result.info.name = name.length > 0 ? name : FormatRegistry.byId('plain').defaultFilename;
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
    if (info.uri.length === 0) throw new Error('没有可写入的文件');
    if (!info.writable) throw new Error('当前文件没有写入权限，请使用“另存为”');
    if (checkConflict) {
      if (info.fingerprint.length === 0) {
        throw new Error('缺少原文件指纹，请使用“另存为”，避免覆盖其他修改。');
      }
      const current = DocumentFiles.readBytes(info.uri);
      if (fingerprintOf(current) !== info.fingerprint) {
        throw new Error('原文件已在其他应用中改变。请选择“另存为”，避免覆盖其他修改。');
      }
    }
    if (info.newline === 'mixed') {
      const parts = text.split('\n');
      if (parts.length !== info.lineEndings.length + 1) {
        throw new Error('混合换行在行数变化后无法无损写回。请使用“另存为”。');
      }
    }
    const encoded = TextEncoding.encode(text, info);
    info.newline = encoded.newline;
    info.lineEndings = encoded.lineEndings;
    const bytes = encoded.bytes;
    const file = fileIo.openSync(info.uri, fileIo.OpenMode.READ_WRITE);
    try {
      let offset = 0;
      while (offset < bytes.length) {
        const remaining = bytes.slice(offset);
        const written = fileIo.writeSync(file.fd, remaining.buffer);
        if (written <= 0) throw new Error('文件写入中断');
        offset += written;
      }
      fileIo.truncateSync(file.fd, bytes.length);
      fileIo.fsyncSync(file.fd);
    } finally {
      fileIo.closeSync(file);
    }
    const verified = DocumentFiles.readBytes(info.uri);
    if (fingerprintOf(verified) !== fingerprintOf(bytes)) {
      throw new Error('保存后校验失败，已保留草稿');
    }
    const decoded = TextEncoding.decode(verified);
    if (decoded.text !== text) throw new Error('保存后校验失败，已保留草稿');
    info.fingerprint = fingerprintOf(verified);
    info.hasBom = decoded.hasBom;
    info.encoding = decoded.encoding;
  }
}
