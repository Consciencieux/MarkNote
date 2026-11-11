import { util } from '@kit.ArkTS';
import { DocumentInfo } from '../model/Document';
import { AppText } from '../i18n/AppText';

export class DecodedText {
  text: string = '';
  encoding: string = 'utf-8';
  hasBom: boolean = false;
  newline: string = '\n';
  lineEndings: string = '';
}

export class EncodedText {
  bytes: Uint8Array = new Uint8Array(0);
  newline: string = '\n';
  lineEndings: string = '';
}

function decodeAs(encoding: string, bytes: Uint8Array): string | null {
  try {
    const decoder = util.TextDecoder.create(encoding, { fatal: true, ignoreBOM: true });
    const value = decoder.decodeToString(bytes);
    return value === undefined ? null : value;
  } catch {
    return null;
  }
}

function utf16Encoding(bytes: Uint8Array): string {
  if (bytes.length < 4 || bytes.length % 2 !== 0) return '';
  let evenZero = 0;
  let oddZero = 0;
  const samples = Math.min(bytes.length, 64);
  for (let index = 0; index + 1 < samples; index += 2) {
    if (bytes[index] === 0) evenZero++;
    if (bytes[index + 1] === 0) oddZero++;
  }
  const pairs = samples / 2;
  if (oddZero > pairs * 0.8 && evenZero < pairs * 0.2) return 'utf-16le';
  if (evenZero > pairs * 0.8 && oddZero < pairs * 0.2) return 'utf-16be';
  return '';
}

/** Editor text uses '\n'. LF, CR and CRLF are restored on save. */
function normalizeNewlines(raw: string): DecodedText {
  const decoded = new DecodedText();
  // Most documents use LF only; avoid constructing a new string one character at a time.
  if (raw.indexOf('\r') < 0) {
    decoded.text = raw;
    return decoded;
  }
  let sawLf = false;
  let sawCr = false;
  let sawCrLf = false;
  for (let index = 0; index < raw.length; index++) {
    const code = raw.charCodeAt(index);
    if (code === 13) {
      decoded.text += '\n';
      if (index + 1 < raw.length && raw.charCodeAt(index + 1) === 10) {
        index++;
        decoded.lineEndings += 'r';
        sawCrLf = true;
      } else {
        decoded.lineEndings += 'c';
        sawCr = true;
      }
    } else if (code === 10) {
      decoded.text += '\n';
      decoded.lineEndings += 'n';
      sawLf = true;
    } else {
      decoded.text += raw[index];
    }
  }
  const kinds = (sawLf ? 1 : 0) + (sawCr ? 1 : 0) + (sawCrLf ? 1 : 0);
  if (kinds > 1) {
    decoded.newline = 'mixed';
  } else if (sawCrLf) {
    decoded.newline = '\r\n';
    decoded.lineEndings = '';
  } else if (sawCr) {
    decoded.newline = '\r';
    decoded.lineEndings = '';
  } else {
    decoded.newline = '\n';
    decoded.lineEndings = '';
  }
  return decoded;
}

function endingMark(mark: string): string {
  if (mark === 'r') return '\r\n';
  if (mark === 'c') return '\r';
  return '\n';
}

function serialize(text: string, newline: string, lineEndings: string, encoding: string): EncodedText {
  const result = new EncodedText();
  const parts = text.split('\n');
  if (newline === 'mixed' && parts.length === lineEndings.length + 1) {
    let mixed = parts[0];
    for (let index = 0; index < lineEndings.length; index++) {
      mixed += endingMark(lineEndings[index]) + parts[index + 1];
    }
    result.newline = 'mixed';
    result.lineEndings = lineEndings;
    result.bytes = encodeBody(mixed, encoding);
    return result;
  }
  if (newline === '\r\n') {
    result.newline = '\r\n';
    result.bytes = encodeBody(text.replace(/\n/g, '\r\n'), encoding);
    return result;
  }
  if (newline === '\r') {
    result.newline = '\r';
    result.bytes = encodeBody(text.replace(/\n/g, '\r'), encoding);
    return result;
  }
  result.newline = '\n';
  result.bytes = encodeBody(text, encoding);
  return result;
}

function encodeBody(value: string, encoding: string): Uint8Array {
  const encoder = util.TextEncoder.create(encoding);
  const encoded = encoder.encodeInto(value);
  return encoded === undefined ? new Uint8Array(0) : encoded;
}

function bomPrefix(encoding: string): Uint8Array {
  if (encoding === 'utf-8') return new Uint8Array([0xEF, 0xBB, 0xBF]);
  if (encoding === 'utf-16le') return new Uint8Array([0xFF, 0xFE]);
  if (encoding === 'utf-16be') return new Uint8Array([0xFE, 0xFF]);
  return new Uint8Array(0);
}

function startsWithBytes(bytes: Uint8Array, prefix: Uint8Array): boolean {
  if (prefix.length === 0 || bytes.length < prefix.length) return false;
  for (let index = 0; index < prefix.length; index++) {
    if (bytes[index] !== prefix[index]) return false;
  }
  return true;
}

export class TextEncoding {
  static decode(bytes: Uint8Array): DecodedText {
    if (bytes.length === 0) return new DecodedText();
    let encoding = 'utf-8';
    let hasBom = false;
    let payload = bytes;
    if (bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) {
      hasBom = true;
      payload = bytes.slice(3);
    } else if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) {
      encoding = 'utf-16le';
      hasBom = true;
      payload = bytes.slice(2);
    } else if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) {
      encoding = 'utf-16be';
      hasBom = true;
      payload = bytes.slice(2);
    } else {
      const hinted = utf16Encoding(bytes);
      if (hinted.length > 0 && decodeAs(hinted, bytes) !== null) encoding = hinted;
    }
    let text: string | null = null;
    if (encoding !== 'utf-8') text = decodeAs(encoding, payload);
    if (text === null) {
      text = decodeAs('utf-8', payload);
      encoding = 'utf-8';
    }
    if (text === null) {
      text = decodeAs('gb18030', payload);
      encoding = 'gb18030';
    }
    if (text === null) throw new Error(AppText.text($r('app.string.encoding_unknown')));
    const decoded = normalizeNewlines(text);
    decoded.encoding = encoding;
    decoded.hasBom = hasBom;
    return decoded;
  }

  static encode(text: string, info: DocumentInfo): EncodedText {
    const encoding = info.encoding.length === 0 ? 'utf-8' : info.encoding;
    const applied = serialize(text, info.newline, info.lineEndings, encoding);
    if (info.hasBom) {
      const prefix = bomPrefix(encoding);
      if (prefix.length > 0 && !startsWithBytes(applied.bytes, prefix)) {
        const bytes = new Uint8Array(prefix.length + applied.bytes.length);
        bytes.set(prefix, 0);
        bytes.set(applied.bytes, prefix.length);
        applied.bytes = bytes;
      }
    }
    const decoded = TextEncoding.decode(applied.bytes);
    if (decoded.text !== text) {
      throw new Error(AppText.text($r('app.string.encoding_lossy')));
    }
    return applied;
  }
}
