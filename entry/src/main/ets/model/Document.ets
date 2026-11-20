import { AppText } from '../i18n/AppText';

/** File-backed document metadata. DocumentService owns the live session; the page mirrors it for ArkUI. */
export class DocumentInfo {
  uri: string = '';
  name: string = AppText.text($r('app.string.file_untitled_md'));
  hasBom: boolean = false;
  /** '\n', '\r', '\r\n', or 'mixed'. Editor text always uses '\n'. */
  newline: string = '\n';
  /** Compact per-line endings when newline is mixed: 'n' LF, 'r' CRLF, 'c' CR. */
  lineEndings: string = '';
  encoding: string = 'utf-8';
  /** SHA-256 of the bytes last read or successfully written. Empty when there is no file yet. */
  fingerprint: string = '';
  /** FormatRegistry id. Empty until a document is created or opened. */
  formatId: string = '';
  /** Granted by opening the file, not inferred from the URI text. */
  writable: boolean = false;
  /** Persisted file grant that can be activated on a later launch. */
  persistent: boolean = false;
}

export function copyInfo(source: DocumentInfo): DocumentInfo {
  const info = new DocumentInfo();
  info.uri = source.uri;
  info.name = source.name;
  info.hasBom = source.hasBom;
  info.newline = source.newline;
  info.lineEndings = source.lineEndings;
  info.encoding = source.encoding;
  info.fingerprint = source.fingerprint;
  info.formatId = source.formatId;
  info.writable = source.writable;
  info.persistent = source.persistent;
  return info;
}

export class RecentDocument {
  uri: string = '';
  name: string = '';
  openedAt: number = 0;
  modifiedAt: number = 0;
  favorite: boolean = false;
  recent: boolean = true;

  constructor(uri: string = '', name: string = '') {
    this.uri = uri;
    this.name = name;
  }
}

export class RecoveryData {
  name: string = AppText.text($r('app.string.file_untitled_md'));
  uri: string = '';
  text: string = '';
  savedText: string = '';
  hasBom: boolean = false;
  newline: string = '\n';
  lineEndings: string = '';
  encoding: string = 'utf-8';
  fingerprint: string = '';
  formatId: string = '';
  writable: boolean = false;
  persistent: boolean = false;
  /** A provider write began but has not been verified. */
  writeUncertain: boolean = false;
  pendingWriteText: string = '';
  pendingWriteUri: string = '';
}

/** Process-only handle for one recovery write. The disk record stays RecoveryData. */
export class DraftSnapshot {
  sessionId: number = 0;
  revision: number = 0;
  data: RecoveryData = new RecoveryData();
}

export class Heading {
  level: number;
  text: string;
  offset: number;

  constructor(level: number, text: string, offset: number) {
    this.level = level;
    this.text = text;
    this.offset = offset;
  }
}

/** ATX headings, ignoring fenced code. Offsets use UTF-16 positions (TextArea's model). */
export function documentOutline(source: string): Heading[] {
  const result: Heading[] = [];
  const rows = source.split('\n');
  let offset = 0;
  let fence = '';
  for (let index = 0; index < rows.length; index++) {
    const row = rows[index];
    const marker = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(row);
    if (fence.length > 0) {
      if (marker && marker[1][0] === fence[0] && marker[1].length >= fence.length &&
        /^[ \t]*$/.test(marker[2])) fence = '';
    } else if (marker && (marker[1][0] === '~' || marker[2].indexOf('`') < 0)) {
      fence = marker[1];
    } else {
      const match = /^ {0,3}(#{1,6})(?=[ \t]|$)/.exec(row);
      if (match) {
        // Closing hashes need preceding whitespace. Keep the hash in titles such as C#.
        const name = row.substring(match[0].length).replace(/[ \t]+#+[ \t]*$/, '').trim();
        if (name.length > 0) result.push(new Heading(match[1].length, name, offset));
      }
    }
    offset += row.length + 1;
  }
  return result;
}
