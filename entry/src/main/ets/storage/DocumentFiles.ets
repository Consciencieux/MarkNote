import { common } from '@kit.AbilityKit';
import { picker, fileIo, fileShare } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { DocumentInfo } from '../model/Document';

const MAX_BYTES: number = 8 * 1024 * 1024;

export class FileContents {
  info: DocumentInfo = new DocumentInfo();
  text: string = '';
}

function decode(bytes: Uint8Array): string {
  const value = util.TextDecoder.create('utf-8').decodeToString(bytes);
  // Decoder replacement characters are unacceptable for source-code editing.
  const roundtrip = new util.TextEncoder().encodeInto(value);
  if (roundtrip.length !== bytes.length) throw new Error('文件不是有效的 UTF-8 编码');
  for (let i = 0; i < bytes.length; i++) {
    if (roundtrip[i] !== bytes[i]) throw new Error('文件不是有效的 UTF-8 编码');
  }
  return value;
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
    options.fileSuffixFilters = ['Markdown|.md,.markdown', 'SVG|.svg', 'LaTeX|.tex', '文本|.txt'];
    const uris = await new picker.DocumentViewPicker(context).select(options);
    return uris.length === 0 ? '' : uris[0];
  }

  static async chooseSave(context: common.UIAbilityContext, filename: string): Promise<string> {
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [filename];
    const choices = ['Markdown|.md', 'SVG|.svg', 'LaTeX|.tex', '文本|.txt'];
    const extension = filename.toLowerCase();
    const preferred = extension.endsWith('.svg') ? 'SVG|.svg' :
      extension.endsWith('.tex') ? 'LaTeX|.tex' :
      extension.endsWith('.txt') ? '文本|.txt' : 'Markdown|.md';
    options.fileSuffixChoices = [preferred, ...choices.filter((choice: string) => choice !== preferred)];
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
      const bom = size >= 3 && original[0] === 239 && original[1] === 187 && original[2] === 191;
      const raw = decode(bom ? original.slice(3) : original);
      const result = new FileContents();
      result.text = raw.replace(/\r\n/g, '\n');
      result.info.uri = uri;
      result.info.name = file.name || '未命名.md';
      result.info.newline = raw.indexOf('\r\n') >= 0 ? '\r\n' : '\n';
      result.info.hasBom = bom;
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
          disk.info.newline !== info.newline) {
        throw new Error('原文件已在其他应用中改变。请选择“另存为”，避免覆盖其他修改。');
      }
    }
    const serialized = info.newline === '\r\n' ? text.replace(/\n/g, '\r\n') : text;
    const source = new util.TextEncoder().encodeInto(serialized);
    const bytes = new Uint8Array(source.length + (info.hasBom ? 3 : 0));
    if (info.hasBom) bytes.set([239, 187, 191], 0);
    bytes.set(source, info.hasBom ? 3 : 0);
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
    if (verified.text !== text || verified.info.hasBom !== info.hasBom) {
      throw new Error('保存后校验失败，已保留草稿');
    }
  }
}
