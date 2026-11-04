/** Static format table. Adding a format is a new entry plus a preview renderer, not a page edit. */
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
  inserts: string[] = [];
  openFilter: string = '';
  saveChoice: string = '';
}

const MARKDOWN_INSERTS: string[] = ['# ', '**', '*', '`', '[]()', '- ', '- [ ] ', '$', '```'];

function format(id: string, sheetTitle: string, moreTitle: string, extensions: string[],
  utds: string[], mimes: string[], defaultFilename: string, starter: string, outline: boolean,
  inserts: string[], openFilter: string, saveChoice: string): DocumentFormat {
  const item = new DocumentFormat();
  item.id = id;
  item.sheetTitle = sheetTitle;
  item.moreTitle = moreTitle;
  item.extensions = extensions;
  item.utds = utds;
  item.mimes = mimes;
  item.defaultFilename = defaultFilename;
  item.starter = starter;
  item.outline = outline;
  item.inserts = inserts;
  item.openFilter = openFilter;
  item.saveChoice = saveChoice;
  return item;
}

const FORMATS: DocumentFormat[] = [
  format('markdown', 'Markdown 文稿', '新建 Markdown', ['.md', '.markdown'],
    ['general.markdown'], ['text/markdown', 'text/x-markdown'],
    '未命名.md', '', true, MARKDOWN_INSERTS, 'Markdown|.md,.markdown', 'Markdown|.md'),
  format('plain', '纯文本', '新建纯文本', ['.txt'],
    ['general.plain-text'], ['text/plain'],
    '未命名.txt', '', false, [], '文本|.txt', '文本|.txt'),
  format('svg', 'SVG 图形', '新建 SVG', ['.svg'],
    ['general.svg-image'], ['image/svg+xml'],
    '未命名.svg',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 160">\n  <circle cx="160" cy="80" r="52" fill="#628ac7"/>\n</svg>',
    false, [], 'SVG|.svg', 'SVG|.svg'),
  format('tex-math', 'LaTeX 数学公式', '新建 LaTeX 公式', ['.tex'],
    ['org.tug.tex', 'general.tex'], ['application/x-tex', 'text/x-tex'],
    '未命名.tex', '\\frac{a}{b} + \\sqrt{x^2 + y^2}',
    false, [], 'LaTeX|.tex', 'LaTeX|.tex')
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
