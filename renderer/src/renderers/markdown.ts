import MarkdownIt, { type Token } from 'markdown-it';
import katex, { type KatexOptions } from 'katex';
import { katex as katexPlugin } from '@mdit/plugin-katex';
import { tasklist } from '@mdit/plugin-tasklist';
import { imagePlaceholder, previewError, previewText } from '../preview-text.ts';
import { indexMarkdown, type MarkdownPages, type MarkdownPage } from './markdown-pages.ts';
import { safeExternalUrl } from './external-link.ts';
import { sanitizeSvg } from './svg.ts';
import { canonicalCodeLanguage } from '../../../shared/code-languages.ts';

export interface CodeJob { id: number; source: string; language: string }
export interface MarkdownRender {
  html: string;
  jobs: CodeJob[];
  diagrams: string[];
}
let nextCodeId = 0;

const md = new MarkdownIt({
  html: false,
  linkify: false,
  typographer: false
});
md.use(tasklist, { disabled: true, label: true });
const mathOptions: KatexOptions = {
  trust: false,
  throwOnError: false,
  maxSize: 100,
  maxExpand: 1000,
  strict: 'warn'
};
md.use(katexPlugin, { ...mathOptions, delimiters: 'all', mathFence: true });

// Keep list numbering and loose paragraphs when rendering a slice of one long list.
md.core.ruler.after('block', 'marknote_list_continuation', state => {
  const page = state.env.page as MarkdownPage | undefined;
  if (page?.orderedStart !== undefined && state.tokens[0]?.tag === 'ol') {
    state.tokens[0].attrSet('start', String(page.orderedStart));
  }
  if (page?.loose) {
    for (const token of state.tokens) {
      if (token.tag === 'p' && token.level === 2) token.hidden = false;
    }
  }
});

function imageAddress(token: { attrGet: (name: string) => string | number | null }): string {
  const src = token.attrGet('src');
  return typeof src === 'string' ? src : '';
}

md.renderer.rules.image = (tokens, idx) => {
  const token = tokens[idx];
  const alt = token.content || previewText().imageName;
  const safeAlt = md.utils.escapeHtml(alt);
  const safeSrc = md.utils.escapeHtml(imageAddress(token));
  // The application resolves this key through the document URI when the slot is visible.
  return `<span class="missing-image image-slot" data-mn-src="${safeSrc}" data-mn-alt="${safeAlt}">${imagePlaceholder(alt)}</span>`;
};
md.renderer.rules.link_open = (tokens, idx, options, _env, self) => {
  const token = tokens[idx];
  const href = token.attrGet('href');
  const address = typeof href === 'string' ? href : '';
  // In-page anchors stay on the preview. Every other address loses href.
  if (address.startsWith('#')) return self.renderToken(tokens, idx, options);
  const index = token.attrIndex('href');
  if (index >= 0 && token.attrs) token.attrs.splice(index, 1);
  const safe = safeExternalUrl(address);
  if (safe) token.attrSet('data-mn-external-url', safe);
  return self.renderToken(tokens, idx, options);
};
const defaultFence = md.renderer.rules.fence!;
md.renderer.rules.fence = (tokens, idx, options, env, renderer) => {
  const info = tokens[idx].info.trim().split(/\s+/)[0]?.toLowerCase();
  if (info === 'svg') return `<section class="svg-canvas">${sanitizeSvg(tokens[idx].content)}</section>`;
  const render = env?.render as MarkdownRender | undefined;
  if (!render) return defaultFence(tokens, idx, options, env, renderer);
  if (info === 'mermaid') {
    const index = render.diagrams.push(tokens[idx].content) - 1;
    return `<section class="mermaid-block" data-mn-mermaid="${index}"></section>`;
  }
  if (info && canonicalCodeLanguage(info)) {
    const id = nextCodeId++;
    render.jobs.push({ id, source: tokens[idx].content, language: info });
    tokens[idx].attrSet('data-mn-code', String(id));
  }
  return defaultFence(tokens, idx, options, env, renderer);
};

// The KaTeX plugin owns a macro namespace for the duration of one md.render.
// Probe actual math tokens with KaTeX so an example in a code block, ordinary
// text, or a local definition does not change a long document's layout.
const globalDefinition = /\\(?:gdef|xdef|global)(?![a-zA-Z])/;

function definesPersistentMacro(token: Token): boolean {
  if (token.type === 'inline') return token.children?.some(definesPersistentMacro) ?? false;
  const display = token.type === 'math_block' || (token.type === 'fence' && token.info.trim() === 'math');
  if ((!display && token.type !== 'math_inline') || !globalDefinition.test(token.content)) return false;
  const macros: NonNullable<KatexOptions['macros']> = {};
  katex.renderToString(token.content, { ...mathOptions, macros, displayMode: display });
  return Object.keys(macros).length > 0;
}

export function markdownPages(source: string): MarkdownPages {
  const document = indexMarkdown(md, source);
  if (document.pages.length < 2 || !globalDefinition.test(source)) return document;
  for (const page of document.pages) {
    const body = document.source.slice(page.from, page.to);
    if (!globalDefinition.test(body)) continue;
    const tokens = md.parse((page.tableHead ?? '') + body, { references: document.env.references });
    if (tokens.some(definesPersistentMacro)) {
      // Keep redefinitions and subsequent formulas in source order, including
      // when the reader jumps directly to a later formula.
      document.pages = [{ from: 0, to: document.source.length, lines: document.pages.reduce((n, p) => n + p.lines, 0) }];
      break;
    }
  }
  return document;
}

export function renderMarkdownPage(document: MarkdownPages, page: MarkdownPage): MarkdownRender {
  const render: MarkdownRender = { html: '', jobs: [], diagrams: [] };
  // Reference definitions are resolved across the whole document. The tasklist
  // plugin also shares a running checkbox ID within this render pass.
  const env = document.env;
  env.render = render;
  env.page = page;
  try {
    render.html = md.render((page.tableHead ?? '') + document.source.slice(page.from, page.to), env);
  } catch {
    render.html = previewError(previewText().markdownFailed);
  } finally {
    delete env.page;
    delete env.render;
  }
  return render;
}
