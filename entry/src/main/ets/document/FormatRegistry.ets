/**
 * Static format table. Adding a format is a new entry plus a preview renderer, not a page edit.
 *
 * Each format also owns its toolbar actions: their labels, system symbols and inserted text.
 */

/** One toolbar action: what to insert, how to label it, and which system symbol represents it. */
export class InsertAction {
  label: string;
  symbol: Resource;
  /** Text placed before the selection. */
  before: string;
  /** Text placed after the selection. */
  after: string;

  constructor(label: string, symbol: Resource, before: string, after: string) {
    this.label = label;
    this.symbol = symbol;
    this.before = before;
    this.after = after;
  }
}

/** Inserts the token as an inline prefix and keeps the cursor inside it, e.g. bold or italic. */
function wrap(token: string, label: string, symbol: Resource): InsertAction {
  return new InsertAction(label, symbol, token, token);
}

/** Inserts the token as a line prefix, e.g. a heading or list marker. */
function prefix(token: string, label: string, symbol: Resource): InsertAction {
  return new InsertAction(label, symbol, token, '');
}

export class DocumentFormat {
  id: string = '';
  sheetTitle: string = '';
  moreTitle: string = '';
  extensions: string[] = [];
  utds: string[] = [];
  mimes: string[] = [];
  defaultFilename: string = '';
  starter: string = '';
  outline: boolean = false;
  inserts: InsertAction[] = [];
  openFilter: string = '';
  saveChoice: string = '';
}

/** Named fields for a format entry. Positional arguments were too easy to misorder. */
interface FormatSpec {
  id: string;
  sheetTitle: string;
  moreTitle: string;
  extensions: string[];
  utds: string[];
  mimes: string[];
  defaultFilename: string;
  starter: string;
  outline: boolean;
  inserts: InsertAction[];
  openFilter: string;
  saveChoice: string;
}

function defineFormat(spec: FormatSpec): DocumentFormat {
  const item = new DocumentFormat();
  item.id = spec.id;
  item.sheetTitle = spec.sheetTitle;
  item.moreTitle = spec.moreTitle;
  item.extensions = spec.extensions;
  item.utds = spec.utds;
  item.mimes = spec.mimes;
  item.defaultFilename = spec.defaultFilename;
  item.starter = spec.starter;
  item.outline = spec.outline;
  item.inserts = spec.inserts;
  item.openFilter = spec.openFilter;
  item.saveChoice = spec.saveChoice;
  return item;
}

const MARKDOWN_INSERTS: InsertAction[] = [
  prefix('# ', '标题', $r('sys.symbol.textformat')),
  wrap('**', '加粗', $r('sys.symbol.bold')),
  wrap('*', '斜体', $r('sys.symbol.italic')),
  wrap('`', '代码', $r('sys.symbol.code')),
  new InsertAction('链接', $r('sys.symbol.link'), '[', '](url)'),
  prefix('- ', '列表', $r('sys.symbol.list_bullet')),
  prefix('- [ ] ', '待办', $r('sys.symbol.checkmark_square')),
  wrap('$', '公式', $r('sys.symbol.sum_rectangle_fill')),
  new InsertAction('代码块', $r('sys.symbol.code_square'), '```\n', '\n```')
];

const FORMATS: DocumentFormat[] = [
  defineFormat({
    id: 'markdown',
    sheetTitle: 'Markdown 文稿',
    moreTitle: '新建 Markdown',
    extensions: ['.md', '.markdown'],
    utds: ['general.markdown'],
    mimes: ['text/markdown', 'text/x-markdown'],
    defaultFilename: '未命名.md',
    starter: '',
    outline: true,
    inserts: MARKDOWN_INSERTS,
    openFilter: 'Markdown|.md,.markdown',
    saveChoice: 'Markdown|.md'
  }),
  defineFormat({
    id: 'plain',
    sheetTitle: '纯文本',
    moreTitle: '新建纯文本',
    extensions: ['.txt'],
    utds: ['general.plain-text'],
    mimes: ['text/plain'],
    defaultFilename: '未命名.txt',
    starter: '',
    outline: false,
    inserts: [],
    openFilter: '文本|.txt',
    saveChoice: '文本|.txt'
  }),
  defineFormat({
    id: 'svg',
    sheetTitle: 'SVG 图形',
    moreTitle: '新建 SVG',
    extensions: ['.svg'],
    utds: ['general.svg-image'],
    mimes: ['image/svg+xml'],
    defaultFilename: '未命名.svg',
    starter: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 160">\n' +
      '  <circle cx="160" cy="80" r="52" fill="#628ac7"/>\n</svg>',
    outline: false,
    inserts: [],
    openFilter: 'SVG|.svg',
    saveChoice: 'SVG|.svg'
  }),
  defineFormat({
    id: 'tex-math',
    sheetTitle: 'LaTeX 文稿',
    moreTitle: '新建 LaTeX',
    extensions: ['.tex'],
    utds: ['org.tug.tex', 'general.tex'],
    mimes: ['application/x-tex', 'text/x-tex'],
    defaultFilename: '未命名.tex',
    starter: '\\frac{a}{b} + \\sqrt{x^2 + y^2}',
    outline: true,
    inserts: [],
    openFilter: 'LaTeX|.tex',
    saveChoice: 'LaTeX|.tex'
  })
];

function extensionOf(filename: string): string {
  const lower = filename.toLowerCase();
  let matched = '';
  for (let index = 0; index < FORMATS.length; index++) {
    const extensions = FORMATS[index].extensions;
    for (let next = 0; next < extensions.length; next++) {
      const extension = extensions[next];
      if (lower.endsWith(extension) && extension.length > matched.length) matched = extension;
    }
  }
  return matched;
}

function findId(id: string): DocumentFormat | null {
  for (let index = 0; index < FORMATS.length; index++) {
    if (FORMATS[index].id === id) return FORMATS[index];
  }
  return null;
}

export class FormatRegistry {
  static all(): DocumentFormat[] {
    return FORMATS;
  }

  static byId(id: string): DocumentFormat {
    const found = findId(id);
    if (found !== null) return found;
    const plain = findId('plain');
    return plain !== null ? plain : FORMATS[0];
  }

  static byFilename(filename: string): DocumentFormat {
    const extension = extensionOf(filename);
    if (extension.length === 0) return FormatRegistry.byId('plain');
    for (let index = 0; index < FORMATS.length; index++) {
      const extensions = FORMATS[index].extensions;
      for (let next = 0; next < extensions.length; next++) {
        if (extensions[next] === extension) return FORMATS[index];
      }
    }
    return FormatRegistry.byId('plain');
  }

  /**
   * Filename extension wins when it is one of ours. Otherwise use the caller's UTD or MIME.
   * Unknown system types stay unresolved so they are not rendered as Markdown.
   * allowUnknown is for the in-app picker, which has already filtered suffixes.
   */
  static resolve(filename: string, declaredType: string, allowUnknown: boolean): DocumentFormat | null {
    const extension = extensionOf(filename);
    if (extension.length > 0) return FormatRegistry.byFilename(filename);
    const declared = FormatRegistry.byDeclaration(declaredType);
    if (declared !== null) return declared;
    if (allowUnknown && declaredType.length === 0) return FormatRegistry.byId('plain');
    return null;
  }

  static byDeclaration(declaredType: string): DocumentFormat | null {
    const normalized = declaredType.toLowerCase().trim();
    if (normalized.length === 0) return null;
    const semi = normalized.indexOf(';');
    const token = semi >= 0 ? normalized.substring(0, semi).trim() : normalized;
    for (let index = 0; index < FORMATS.length; index++) {
      const item = FORMATS[index];
      for (let next = 0; next < item.utds.length; next++) {
        if (item.utds[next] === token) return item;
      }
      for (let next = 0; next < item.mimes.length; next++) {
        if (item.mimes[next] === token) return item;
      }
    }
    return null;
  }

  static openFilters(): string[] {
    const filters: string[] = [];
    for (let index = 0; index < FORMATS.length; index++) filters.push(FORMATS[index].openFilter);
    return filters;
  }

  static saveChoices(filename: string): string[] {
    const preferred = FormatRegistry.byFilename(filename).saveChoice;
    const choices: string[] = [preferred];
    for (let index = 0; index < FORMATS.length; index++) {
      if (FORMATS[index].saveChoice !== preferred) choices.push(FORMATS[index].saveChoice);
    }
    return choices;
  }
}
