/** Static format table. Adding a format is a new entry plus a preview renderer, not a page edit. */
export class DocumentFormat {
  id: string = '';
  sheetTitle: string = '';
  moreTitle: string = '';
  extensions: string[] = [];
  defaultFilename: string = '';
  starter: string = '';
  outline: boolean = false;
  inserts: string[] = [];
  openFilter: string = '';
  saveChoice: string = '';
}

const MARKDOWN_INSERTS: string[] = ['# ', '**', '*', '`', '[]()', '- ', '- [ ] ', '$', '```'];

function format(id: string, sheetTitle: string, moreTitle: string, extensions: string[],
  defaultFilename: string, starter: string, outline: boolean, inserts: string[],
  openFilter: string, saveChoice: string): DocumentFormat {
  const item = new DocumentFormat();
  item.id = id;
  item.sheetTitle = sheetTitle;
  item.moreTitle = moreTitle;
  item.extensions = extensions;
  item.defaultFilename = defaultFilename;
  item.starter = starter;
  item.outline = outline;
  item.inserts = inserts;
  item.openFilter = openFilter;
  item.saveChoice = saveChoice;
  return item;
}

const FORMATS: DocumentFormat[] = [
  format('markdown', 'Markdown 文稿', '新建 Markdown', ['.md', '.markdown'], '未命名.md', '',
    true, MARKDOWN_INSERTS, 'Markdown|.md,.markdown', 'Markdown|.md'),
  format('plain', '纯文本', '新建纯文本', ['.txt'], '未命名.txt', '',
    false, [], '文本|.txt', '文本|.txt'),
  format('svg', 'SVG 图形', '新建 SVG', ['.svg'], '未命名.svg',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 160">\n  <circle cx="160" cy="80" r="52" fill="#628ac7"/>\n</svg>',
    false, [], 'SVG|.svg', 'SVG|.svg'),
  format('tex-math', 'LaTeX 数学公式', '新建 LaTeX 公式', ['.tex'], '未命名.tex',
    '\\frac{a}{b} + \\sqrt{x^2 + y^2}',
    false, [], 'LaTeX|.tex', 'LaTeX|.tex')
];

export class FormatRegistry {
  static all(): DocumentFormat[] {
    return FORMATS;
  }

  static byId(id: string): DocumentFormat {
    for (let index = 0; index < FORMATS.length; index++) {
      if (FORMATS[index].id === id) return FORMATS[index];
    }
    return FORMATS[0];
  }

  static byFilename(filename: string): DocumentFormat {
    const lower = filename.toLowerCase();
    for (let index = 0; index < FORMATS.length; index++) {
      const extensions = FORMATS[index].extensions;
      for (let next = 0; next < extensions.length; next++) {
        if (lower.endsWith(extensions[next])) return FORMATS[index];
      }
    }
    return FormatRegistry.byId('plain');
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
