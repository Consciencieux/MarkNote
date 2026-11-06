/** File-backed document metadata. DocumentService owns the live session; the page mirrors it for ArkUI. */
export class DocumentInfo {
  uri: string = '';
  name: string = '未命名.md';
  hasBom: boolean = false;
  /** '\n', '\r\n', or 'mixed'. Editor text always uses '\n'. */
  newline: string = '\n';
  /** Compact per-line endings when newline is mixed: 'n' or 'r' for each break. */
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

  constructor(uri: string = '', name: string = '') {
    this.uri = uri;
    this.name = name;
  }
}

export class RecoveryData {
  name: string = '未命名.md';
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
}

export class Heading {
  level: number;
  text: string;
  offset: number;
  line: number;

  constructor(level: number, text: string, offset: number, line: number) {
    this.level = level;
    this.text = text;
    this.offset = offset;
    this.line = line;
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
    const marker = /^ {0,3}(`{3,}|~{3,})/.exec(row);
    if (marker) {
      const found = marker[1];
      if (fence.length === 0) {
        fence = found;
      } else if (found[0] === fence[0] && found.length >= fence.length) {
        fence = '';
      }
    } else if (fence.length === 0) {
      const match = /^ {0,3}(#{1,6})\s+(.+?)\s*#*\s*$/.exec(row);
      if (match) {
        const name = match[2].trim();
        if (name.length > 0) result.push(new Heading(match[1].length, name, offset, index + 1));
      }
    }
    offset += row.length + 1;
  }
  return result;
}
