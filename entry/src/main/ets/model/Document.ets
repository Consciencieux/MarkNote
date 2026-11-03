/** File-backed document metadata. The editable text itself is owned by the page. */
export class DocumentInfo {
  uri: string = '';
  name: string = '未命名.md';
  hasBom: boolean = false;
  newline: string = '\n';
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

export function linesIn(source: string): number {
  if (source.length === 0) return 1;
  let count = 1;
  for (let i = 0; i < source.length; i++) {
    if (source.charCodeAt(i) === 10) count++;
  }
  return count;
}
