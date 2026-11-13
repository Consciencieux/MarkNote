import { AppText } from '../i18n/AppText';

/**
 * Static format table. Adding a format is a new entry plus a preview renderer, not a page edit.
 *
 * Each format also owns its toolbar actions: their labels, system symbols and inserted text.
 * Display names come from string resources so they follow the system language.
 */

/** One toolbar action: what to insert, how to label it, and which system symbol represents it. */
export class InsertAction {
  id: string;
  label: Resource;
  symbol: Resource;
  /** Text placed before the selection. */
  before: string;
  /** Text placed after the selection. */
  after: string;

  constructor(id: string, label: Resource, symbol: Resource, before: string, after: string) {
    this.id = id;
    this.label = label;
    this.symbol = symbol;
    this.before = before;
    this.after = after;
  }
}

/** Inserts the token as an inline prefix and keeps the cursor inside it, e.g. bold or italic. */
function wrap(token: string, id: string, label: Resource, symbol: Resource): InsertAction {
  return new InsertAction(id, label, symbol, token, token);
}

/** Inserts the token as a line prefix, e.g. a heading or list marker. */
function prefix(token: string, id: string, label: Resource, symbol: Resource): InsertAction {
  return new InsertAction(id, label, symbol, token, '');
}

export class DocumentFormat {
  id: string = '';
  sheetTitle: Resource = $r('app.string.format_markdown_sheet');
  extensions: string[] = [];
  utds: string[] = [];
  mimes: string[] = [];
  defaultFilename: Resource = $r('app.string.file_untitled_md');
  starter: string = '';
  outline: boolean = false;
  inserts: InsertAction[] = [];
  pickerLabel: Resource = $r('app.string.format_markdown_picker');
  openSuffix: string = '';
  saveSuffix: string = '';
}

/** Named fields for a format entry. Positional arguments were too easy to misorder. */
interface FormatSpec {
  id: string;
  sheetTitle: Resource;
  extensions: string[];
  utds: string[];
  mimes: string[];
  defaultFilename: Resource;
  starter: string;
  outline: boolean;
  inserts: InsertAction[];
  pickerLabel: Resource;
  openSuffix: string;
  saveSuffix: string;
}

function defineFormat(spec: FormatSpec): DocumentFormat {
  const item = new DocumentFormat();
  item.id = spec.id;
  item.sheetTitle = spec.sheetTitle;
  item.extensions = spec.extensions;
  item.utds = spec.utds;
  item.mimes = spec.mimes;
  item.defaultFilename = spec.defaultFilename;
  item.starter = spec.starter;
  item.outline = spec.outline;
  item.inserts = spec.inserts;
  item.pickerLabel = spec.pickerLabel;
  item.openSuffix = spec.openSuffix;
  item.saveSuffix = spec.saveSuffix;
  return item;
}

function pickerChoice(label: Resource, suffix: string): string {
  return AppText.text(label) + '|' + suffix;
}

const MARKDOWN_INSERTS: InsertAction[] = [
  prefix('# ', 'md-heading', $r('app.string.insert_heading'), $r('sys.symbol.textformat')),
  wrap('**', 'md-bold', $r('app.string.insert_bold'), $r('sys.symbol.bold')),
  wrap('*', 'md-italic', $r('app.string.insert_italic'), $r('sys.symbol.italic')),
  wrap('`', 'md-code', $r('app.string.insert_code'), $r('sys.symbol.code')),
  new InsertAction('md-link', $r('app.string.insert_link'), $r('sys.symbol.link'), '[', '](url)'),
  prefix('- ', 'md-list', $r('app.string.insert_list'), $r('sys.symbol.list_bullet')),
  prefix('- [ ] ', 'md-task', $r('app.string.insert_task'), $r('sys.symbol.checkmark_square')),
  wrap('$', 'md-math', $r('app.string.insert_math'), $r('sys.symbol.sum_rectangle_fill')),
  new InsertAction('md-code-block', $r('app.string.insert_code_block'), $r('sys.symbol.code_square'), '```\n', '\n```')
];

const LATEX_INSERTS: InsertAction[] = [
  new InsertAction('tex-section', $r('app.string.insert_section'), $r('sys.symbol.textformat'), '\\section{', '}'),
  new InsertAction('tex-subsection', $r('app.string.insert_subsection'), $r('sys.symbol.textformat'), '\\subsection{', '}'),
  new InsertAction('tex-bold', $r('app.string.insert_bold'), $r('sys.symbol.bold'), '\\textbf{', '}'),
  new InsertAction('tex-italic', $r('app.string.insert_italic'), $r('sys.symbol.italic'), '\\emph{', '}'),
  new InsertAction('tex-code', $r('app.string.insert_code'), $r('sys.symbol.code'), '\\texttt{', '}'),
  wrap('$', 'tex-math', $r('app.string.insert_math'), $r('sys.symbol.sum_rectangle_fill')),
  new InsertAction('tex-math-block', $r('app.string.insert_math_block'), $r('sys.symbol.sum_rectangle_fill'), '\\[\n', '\n\\]')
];

const FORMATS: DocumentFormat[] = [
  defineFormat({
    id: 'markdown',
    sheetTitle: $r('app.string.format_markdown_sheet'),
    extensions: ['.md', '.markdown'],
    utds: ['general.markdown'],
    mimes: ['text/markdown', 'text/x-markdown'],
    defaultFilename: $r('app.string.file_untitled_md'),
    starter: '',
    outline: true,
    inserts: MARKDOWN_INSERTS,
    pickerLabel: $r('app.string.format_markdown_picker'),
    openSuffix: '.md,.markdown',
    saveSuffix: '.md'
  }),
  defineFormat({
    id: 'plain',
    sheetTitle: $r('app.string.format_plain_sheet'),
    extensions: ['.txt'],
    utds: ['general.plain-text'],
    mimes: ['text/plain'],
    defaultFilename: $r('app.string.file_untitled_txt'),
    starter: '',
    outline: false,
    inserts: [],
    pickerLabel: $r('app.string.format_plain_picker'),
    openSuffix: '.txt',
    saveSuffix: '.txt'
  }),
  defineFormat({
    id: 'svg',
    sheetTitle: $r('app.string.format_svg_sheet'),
    extensions: ['.svg'],
    utds: ['general.svg-image'],
    mimes: ['image/svg+xml'],
    defaultFilename: $r('app.string.file_untitled_svg'),
    starter: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 160">\n' +
      '  <circle cx="160" cy="80" r="52" fill="#628ac7"/>\n</svg>',
    outline: false,
    inserts: [],
    pickerLabel: $r('app.string.format_svg_picker'),
    openSuffix: '.svg',
    saveSuffix: '.svg'
  }),
  defineFormat({
    id: 'tex-math',
    sheetTitle: $r('app.string.format_latex_sheet'),
    extensions: ['.tex'],
    utds: ['org.tug.tex', 'general.tex'],
    mimes: ['application/x-tex', 'text/x-tex'],
    defaultFilename: $r('app.string.file_untitled_tex'),
    starter: '\\frac{a}{b} + \\sqrt{x^2 + y^2}',
    outline: true,
    inserts: LATEX_INSERTS,
    pickerLabel: $r('app.string.format_latex_picker'),
    openSuffix: '.tex',
    saveSuffix: '.tex'
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

  static displayTitle(format: DocumentFormat): string {
    return AppText.text(format.sheetTitle);
  }

  static defaultName(format: DocumentFormat): string {
    return AppText.text(format.defaultFilename);
  }

  static openFilters(): string[] {
    const filters: string[] = [];
    for (let index = 0; index < FORMATS.length; index++) {
      const item = FORMATS[index];
      filters.push(pickerChoice(item.pickerLabel, item.openSuffix));
    }
    return filters;
  }

  static saveChoices(filename: string): string[] {
    const preferred = FormatRegistry.byFilename(filename);
    const choices: string[] = [pickerChoice(preferred.pickerLabel, preferred.saveSuffix)];
    for (let index = 0; index < FORMATS.length; index++) {
      const item = FORMATS[index];
      if (item.id !== preferred.id) choices.push(pickerChoice(item.pickerLabel, item.saveSuffix));
    }
    return choices;
  }
}
