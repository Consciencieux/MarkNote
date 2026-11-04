import DOMPurify from 'dompurify';
import 'katex/dist/katex.min.css';
import './styles.css';
import { renderMarkdown } from './renderers/markdown';
import { renderPlain } from './renderers/plain';
import { installReferenceHook, sanitizeSvg } from './renderers/svg';
import { renderTexMath } from './renderers/tex-math';

type Kind = 'markdown' | 'plain' | 'svg' | 'tex-math';
type Theme = 'system' | 'light' | 'dark';
interface PreviewUpdate { kind: Kind; source: string; theme: Theme }

const host = document.getElementById('preview');
if (!host) throw new Error('missing preview root');

function renderBody(kind: Kind, source: string): string {
  if (kind === 'svg') return `<section class="svg-canvas">${sanitizeSvg(source)}</section>`;
  if (kind === 'tex-math') return renderTexMath(source);
  if (kind === 'plain') return renderPlain(source);
  return renderMarkdown(source);
}

function render(update: PreviewUpdate): void {
  if (!['system', 'light', 'dark'].includes(update.theme)) return;
  if (!['markdown', 'plain', 'svg', 'tex-math'].includes(update.kind)) return;
  if (typeof update.source !== 'string') return;
  document.documentElement.removeAttribute('data-theme');
  if (update.theme !== 'system') document.documentElement.dataset.theme = update.theme;
  if (!DOMPurify.isSupported) {
    host!.textContent = '当前浏览器不支持安全渲染';
    return;
  }
  if (!update.source.trim()) {
    host!.replaceChildren();
    const empty = document.createElement('p');
    empty.className = 'placeholder';
    empty.textContent = '内容将在这里预览';
    host!.append(empty);
    return;
  }
  installReferenceHook();
  const html = renderBody(update.kind, update.source);
  host!.innerHTML = DOMPurify.sanitize(html, {
    USE_PROFILES: { html: true, svg: true, svgFilters: true, mathMl: true },
    FORBID_TAGS: ['script', 'iframe', 'object', 'embed', 'foreignObject', 'video', 'audio', 'form'],
    FORBID_ATTR: ['src', 'srcset', 'target', 'formaction'],
    SANITIZE_NAMED_PROPS: false
  });
}

const api = Object.freeze({ update: (data: PreviewUpdate) => render(data) });
Object.defineProperty(window, 'MarknotePreview', { value: api, writable: false, configurable: false });
render({ kind: 'markdown', source: '', theme: 'system' });
