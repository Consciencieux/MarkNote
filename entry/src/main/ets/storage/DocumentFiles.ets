import { common } from '@kit.AbilityKit';
import { picker, fileIo, fileShare } from '@kit.CoreFileKit';
import { DocumentInfo } from '../model/Document';
import { FormatRegistry } from '../document/FormatRegistry';
import { TextEncoding } from '../document/TextEncoding';

const MAX_BYTES: number = 8 * 1024 * 1024;

export class FileContents {
  info: DocumentInfo = new DocumentInfo();
  text: string = '';
}

function accessPolicy(uri: string): fileShare.PolicyInfo {
  return {
    uri: uri,
    operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
  };
}

export class DocumentFiles {
  /**
   * Picker grants last only for the current process. Recent files and drafts need the
   * grant persisted, then activated again on the next launch before the URI can be read.
   */
  static async prepare(uri: string): Promise<void> {
    if (uri.length === 0) return;
    const policy = accessPolicy(uri);
    let persisted = false;
    try {
      const states = await fileShare.checkPersistentPermission([policy]);
      persisted = states.length > 0 && states[0];
    } catch {
      persisted = false;
    }
    if (!persisted) {
      try {
        await fileShare.persistPermission([policy]);
        persisted = true;
      } catch {
        persisted = false;
      }
    }
    if (persisted) {
      try {
        await fileShare.activatePermission([policy]);
      } catch {
        // A picker grant from this process can still read before it is persisted.
      }
    }
  }

  static async release(uri: string): Promise<void> {
    if (uri.length === 0) return;
    try {
      await fileShare.revokePermission([accessPolicy(uri)]);
    } catch {
      // The persisted grant may already have been removed.
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

  static read(uri: string): FileContents {
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
      const decoded = TextEncoding.decode(original);
      const result = new FileContents();
      result.text = decoded.text;
      result.info.uri = uri;
      result.info.name = file.name || FormatRegistry.byFilename('').defaultFilename;
      result.info.newline = decoded.newline;
      result.info.lineEndings = decoded.lineEndings;
      result.info.hasBom = decoded.hasBom;
      result.info.encoding = decoded.encoding;
      return result;
    } finally {
      fileIo.closeSync(file);
    }
  }

  /**
   * Outside providers cannot guarantee atomic replacement. Check the last known bytes
   * before writing; verify afterwards. The page keeps its recovery draft on any failure.
   */
  static write(info: DocumentInfo, text: string, expectedSource: string | null): void {
    if (expectedSource !== null) {
      const disk = DocumentFiles.read(info.uri);
      if (disk.text !== expectedSource || disk.info.hasBom !== info.hasBom ||
          disk.info.newline !== info.newline || disk.info.lineEndings !== info.lineEndings ||
          disk.info.encoding !== info.encoding) {
        throw new Error('原文件已在其他应用中改变。请选择“另存为”，避免覆盖其他修改。');
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
    const verified = DocumentFiles.read(info.uri);
    if (verified.text !== text || verified.info.hasBom !== info.hasBom ||
        verified.info.encoding !== info.encoding) {
      throw new Error('保存后校验失败，已保留草稿');
    }
  }
}
