import MarkdownIt from 'markdown-it';
import { katex as katexPlugin } from '@mdit/plugin-katex';
import { tasklist } from '@mdit/plugin-tasklist';
import { imagePlaceholder, previewError, previewText } from '../preview-text.ts';
import { highlightFencedCode } from './code-highlight.ts';
import { beginMermaidDiagrams, mermaidPlaceholder } from './mermaid-block.ts';
import { safeExternalUrl } from './external-link.ts';
import { sanitizeSvg } from './svg.ts';
import { canonicalCodeLanguage } from '../../../shared/code-languages.ts';

export interface CodeJob { id: number; source: string; language: string }
let deferredJobs: CodeJob[] | undefined;

const md = new MarkdownIt({
  html: false,
  linkify: false,
  typographer: false,
  highlight: (source: string, language: string): string => deferredJobs ? '' : highlightFencedCode(source, language)
});
md.use(tasklist, { disabled: true, label: true });
md.use(katexPlugin, {
  delimiters: 'all',
  mathFence: true,
  trust: false,
  throwOnError: false,
  maxSize: 100,
  maxExpand: 1000,
  strict: 'warn'
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
  // 不写 src。页面只在应用传入已读取的 data URL 时，才把这个占位换成图片。
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
  if (info === 'mermaid') return mermaidPlaceholder(tokens[idx].content);
  if (deferredJobs && info && canonicalCodeLanguage(info)) {
    const id = deferredJobs.length;
    deferredJobs.push({ id, source: tokens[idx].content, language: info });
    tokens[idx].attrSet('data-mn-code', String(id));
  }
  return defaultFence(tokens, idx, options, env, renderer);
};

export function renderMarkdown(source: string): string {
  beginMermaidDiagrams();
  try {
    return md.render(source);
  } catch {
    return previewError(previewText().markdownFailed);
  }
}

/** Render immediately with escaped text; callers can apply colors asynchronously. */
export function renderMarkdownDeferred(source: string): { html: string; jobs: CodeJob[] } {
  const jobs: CodeJob[] = [];
  deferredJobs = jobs;
  try {
    return { html: renderMarkdown(source), jobs };
  } finally {
    deferredJobs = undefined;
  }
}
