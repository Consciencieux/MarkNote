import MarkdownIt from 'markdown-it';
import { katex as katexPlugin } from '@mdit/plugin-katex';
import { sanitizeSvg } from './svg';

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
md.renderer.rules.image = (tokens, idx) => {
  const alt = tokens[idx].content || '图片';
  return `<span title="已禁用外部图片">[图片：${md.utils.escapeHtml(alt)}]</span>`;
};
const defaultFence = md.renderer.rules.fence!;
md.renderer.rules.fence = (tokens, idx, options, env, renderer) => {
  const info = tokens[idx].info.trim().split(/\s+/)[0]?.toLowerCase();
  if (info === 'svg') return `<section class="svg-canvas">${sanitizeSvg(tokens[idx].content)}</section>`;
  return defaultFence(tokens, idx, options, env, renderer);
};

export function renderMarkdown(source: string): string {
  try {
    return md.render(source);
  } catch {
    return '<p class="error">Markdown 排版失败，请检查文稿。</p>';
  }
}
