import MarkdownIt from 'markdown-it';
import { katex as katexPlugin } from '@mdit/plugin-katex';
import { imagePlaceholder, previewError, previewText } from '../preview-text.ts';
import { beginMermaidDiagrams, mermaidPlaceholder } from './mermaid-block.ts';
import { sanitizeSvg } from './svg.ts';

const md = new MarkdownIt({ html: false, linkify: false, typographer: false });
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
const defaultFence = md.renderer.rules.fence!;
md.renderer.rules.fence = (tokens, idx, options, env, renderer) => {
  const info = tokens[idx].info.trim().split(/\s+/)[0]?.toLowerCase();
  if (info === 'svg') return `<section class="svg-canvas">${sanitizeSvg(tokens[idx].content)}</section>`;
  if (info === 'mermaid') return mermaidPlaceholder(tokens[idx].content);
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
