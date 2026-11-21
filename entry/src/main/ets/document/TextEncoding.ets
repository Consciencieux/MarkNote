import { util } from '@kit.ArkTS';
import { i18n } from '@kit.LocalizationKit';
import { DocumentInfo } from '../model/Document';
import { AppText } from '../i18n/AppText';
import { userNotice } from './UserNotice';

export const ENCODING_SAMPLE_BYTES: number = 64 * 1024;
const ENCODE_CHARS: number = 32 * 1024;

export class DecodedText {
  text: string = '';
  encoding: string = 'utf-8';
  hasBom: boolean = false;
  newline: string = '\n';
  lineEndings: string = '';
}

export class EncodingProbe {
  encodings: string[] = [];
  bomLength: number = 0;
}

function bomPrefix(encoding: string): Uint8Array {
  if (encoding === 'utf-8') return new Uint8Array([0xEF, 0xBB, 0xBF]);
  if (encoding === 'utf-16le') return new Uint8Array([0xFF, 0xFE]);
  if (encoding === 'utf-16be') return new Uint8Array([0xFE, 0xFF]);
  return new Uint8Array(0);
}

function endingMark(mark: string): string {
  if (mark === 'r') return '\r\n';
  if (mark === 'c') return '\r';
  return '\n';
}

/** One strict decoding attempt. During save verification, only the comparison cursor is retained. */
export class DocumentDecoder {
  private decoder: util.TextDecoder;
  private pendingCr: boolean = false;
  private textParts: string[] = [];
  private firstMark: string = '';
  private endingCount: number = 0;
  private mixed: boolean = false;
  private endingParts: string[] = [];
  private compared: number = 0;
  private matches: boolean = true;
  private expected: string | null;

  constructor(encoding: string, expected: string | null) {
    // HarmonyOS ignoreBOM=false keeps payload U+FEFF. The file marker is removed by the caller.
    this.decoder = util.TextDecoder.create(encoding, { fatal: true, ignoreBOM: false });
    this.expected = expected;
  }

  /** A decoding failure allows the caller to try the next encoding. */
  push(bytes: Uint8Array, last: boolean): boolean {
    if (bytes.length === 0) return true;
    let raw: string;
    try {
      raw = this.decoder.decodeToString(bytes, { stream: !last });
    } catch {
      return false;
    }
    if (raw === undefined) return false;
    if (this.pendingCr) raw = '\r' + raw;
    this.pendingCr = !last && raw.endsWith('\r');
    if (this.pendingCr) raw = raw.slice(0, -1);
    const text = raw.indexOf('\r') < 0 ? raw : raw.replace(/\r\n?/g, '\n');
    if (this.expected !== null) {
      if (this.matches && !this.expected.startsWith(text, this.compared)) this.matches = false;
      this.compared += text.length;
    } else {
      this.textParts.push(text);
      this.recordEndings(raw);
    }
    return true;
  }

  private recordEndings(raw: string): void {
    if (raw.indexOf('\n') < 0 && raw.indexOf('\r') < 0) return;
    // Remember only a count while all line endings agree.
    if (!this.mixed) {
      let count = 0;
      for (let index = 0; index < raw.length; index++) {
        const code = raw.charCodeAt(index);
        let mark: string;
        if (code === 10) mark = 'n';
        else if (code === 13) {
          if (raw.charCodeAt(index + 1) === 10) {
            mark = 'r';
            index++;
          } else mark = 'c';
        } else continue;
        if (this.firstMark === '') this.firstMark = mark;
        if (this.firstMark !== mark) {
          this.mixed = true;
          this.endingParts.push(this.firstMark.repeat(this.endingCount));
          break;
        }
        count++;
      }
      if (!this.mixed) {
        this.endingCount += count;
        return;
      }
    }
    // Build one compact mark string per block, including the prefix of the first mixed block.
    this.endingParts.push(raw.replace(/[^\r\n]+|\r\n|[\r\n]/g, (value: string): string => {
      if (value === '\r\n') return 'r';
      if (value === '\r') return 'c';
      if (value === '\n') return 'n';
      return '';
    }));
  }

  finish(encoding: string, hasBom: boolean): DecodedText {
    if (this.expected !== null && (!this.matches || this.compared !== this.expected.length)) {
      throw userNotice(AppText.text($r('app.string.encoding_lossy')));
    }
    const result = new DecodedText();
    result.encoding = encoding;
    result.hasBom = hasBom;
    result.text = this.textParts.join('');
    result.newline = this.mixed ? 'mixed' : endingMark(this.firstMark);
    if (this.mixed) result.lineEndings = this.endingParts.join('');
    return result;
  }
}

export class TextEncoding {
  static probe(sample: Uint8Array, size: number, requested: string = ''): EncodingProbe {
    const result = new EncodingProbe();
    if (sample.length >= 3 && sample[0] === 0xEF && sample[1] === 0xBB && sample[2] === 0xBF) {
      result.encodings.push('utf-8');
      result.bomLength = 3;
    } else if (sample.length >= 2 && sample[0] === 0xFF && sample[1] === 0xFE) {
      result.encodings.push('utf-16le');
      result.bomLength = 2;
    } else if (sample.length >= 2 && sample[0] === 0xFE && sample[1] === 0xFF) {
      result.encodings.push('utf-16be');
      result.bomLength = 2;
    } else if (requested) {
      result.encodings.push(requested);
    } else {
      // UTF-16 may also form valid UTF-8 bytes. Try the system's UTF-16 hint first.
      // Prefer strict UTF-8 to GB18030 when both can decode the same unmarked bytes.
      if (sample.length > 0 && size % 2 === 0) {
        try {
          const detected = i18n.Unicode.detectEncoding(sample).encodingName.toLowerCase();
          if (detected === 'utf-16le' || detected === 'utf-16be') result.encodings.push(detected);
        } catch { /* Continue with strict decoding. */ }
      }
      result.encodings.push('utf-8', 'gb18030');
    }
    return result;
  }

  static async encode(text: string, info: DocumentInfo, consume: (bytes: Uint8Array) => Promise<void>): Promise<void> {
    const encoding = info.encoding || 'utf-8';
    const encoder = util.TextEncoder.create(encoding);
    const prefix = bomPrefix(encoding);
    if (info.hasBom && prefix.length > 0) await consume(prefix);
    let line = 0;
    let previousWasCr: boolean = false;
    let offset = 0;
    while (offset < text.length) {
      let end = Math.min(text.length, offset + ENCODE_CHARS);
      const tail = text.charCodeAt(end - 1);
      if (end < text.length && tail >= 0xD800 && tail <= 0xDBFF) end--;
      let part = text.substring(offset, end);
      if (info.newline === 'mixed') {
        const input = part;
        let lastCr: boolean = previousWasCr;
        part = input.replace(/\n/g, (_break: string, index: number): string => {
          const mark = info.lineEndings.charAt(line++);
          const adjacentCr: boolean = index === 0 ? previousWasCr : input[index - 1] === '\n' && lastCr;
          lastCr = mark === 'c';
          // After a join, adjacent CR and LF would decode as a single separator.
          return adjacentCr && mark === 'n' ? '\r\n' : endingMark(mark);
        });
        previousWasCr = input.endsWith('\n') && lastCr;
      } else if (info.newline === '\r' || info.newline === '\r\n') {
        part = part.replace(/\n/g, info.newline);
      }
      const bytes = encoder.encodeInto(part);
      if (bytes === undefined || bytes.length === 0) throw userNotice(AppText.text($r('app.string.encoding_lossy')));
      await consume(bytes);
      offset = end;
    }
    if (info.newline === 'mixed' && line !== info.lineEndings.length) {
      throw userNotice(AppText.text($r('app.string.encoding_lossy')));
    }
  }

  static lineBreakCount(text: string): number {
    let count = 0;
    for (let index = text.indexOf('\n'); index >= 0; index = text.indexOf('\n', index + 1)) count++;
    return count;
  }
}
