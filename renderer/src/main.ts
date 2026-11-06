import DOMPurify from 'dompurify';
import 'katex/dist/katex.min.css';
import './styles.css';
import { renderMarkdown } from './renderers/markdown';
import { renderPlain } from './renderers/plain';
import { installReferenceHook, sanitizeSvg } from './renderers/svg';
import { renderTexDocument, type TexDocument } from './renderers/tex';
import type { PreviewUpdate } from './globals';
import katex from 'katex';

type Kind = PreviewUpdate['kind'];
let resultPort: MessagePort | undefined;
let lastResult: string | undefined;
let lastRendered: { kind: Kind; source: string; tex?: TexDocument } | undefined;
window.addEventListener('message', (event: MessageEvent) => {
  if (event.data !== '__marknote_parse_port__' || !event.ports[0]) return;
  resultPort?.close();
  resultPort = event.ports[0];
  if (lastResult) resultPort.postMessage(lastResult);
});

const host = document.getElementById('preview');
if (!host) throw new Error('missing preview root');

function renderBody(kind: Kind, source: string): string {
  if (kind === 'svg') return `<section class="svg-canvas">${sanitizeSvg(source)}</section>`;
  if (kind === 'plain') return renderPlain(source);
  return renderMarkdown(source);
}

function render(update: PreviewUpdate): void {
  if (!['system', 'light', 'dark'].includes(update.theme)) return;
  if (!['markdown', 'plain', 'svg', 'tex-math'].includes(update.kind)) return;
  if (typeof update.source !== 'string') return;
  document.documentElement.removeAttribute('data-theme');
  if (update.theme !== 'system') document.documentElement.dataset.theme = update.theme;
  // Theme changes only affect CSS. Avoid parsing and rebuilding a potentially large document.
  if (lastRendered?.kind === update.kind && lastRendered.source === update.source) {
    if (lastRendered.tex) {
      lastResult = JSON.stringify({ kind: 'tex-outline', revision: update.revision,
        headings: lastRendered.tex.headings, diagnostics: lastRendered.tex.diagnostics });
      resultPort?.postMessage(lastResult);
    }
    return;
  }
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
    lastRendered = { kind: update.kind, source: update.source };
    if (update.kind === 'tex-math') {
      lastResult = JSON.stringify({ kind: 'tex-outline', revision: update.revision, headings: [], diagnostics: [] });
      resultPort?.postMessage(lastResult);
    }
    return;
  }
  installReferenceHook();
  let tex: TexDocument | undefined;
  let html: string;
  try {
    tex = update.kind === 'tex-math' ? renderTexDocument(update.source) : undefined;
    html = tex ? tex.html : renderBody(update.kind, update.source);
  } catch {
    lastRendered = undefined;
    host!.textContent = '预览失败，请检查文稿内容。';
    return;
  }
  host!.innerHTML = DOMPurify.sanitize(html, {
    USE_PROFILES: { html: true, svg: true, svgFilters: true, mathMl: true },
    FORBID_TAGS: ['script', 'iframe', 'object', 'embed', 'foreignObject', 'video', 'audio', 'form'],
    FORBID_ATTR: ['src', 'srcset', 'target', 'formaction'],
    SANITIZE_NAMED_PROPS: false
  });
  lastRendered = { kind: update.kind, source: update.source, tex };
  if (tex) {
    for (const element of host!.querySelectorAll<HTMLElement>('.math-inline, .math-display')) {
      katex.render(element.textContent ?? '', element, {
        displayMode: element.classList.contains('math-display'), throwOnError: false,
        trust: false, strict: 'warn', maxSize: 100, maxExpand: 1000, output: 'htmlAndMathml'
      });
    }
    if (tex.diagnostics.length) {
      const notice = document.createElement('p');
      notice.className = 'error';
      notice.textContent = '部分 LaTeX 内容暂不支持，预览可能不完整。';
      host!.prepend(notice);
    }
    lastResult = JSON.stringify({ kind: 'tex-outline', revision: update.revision,
      headings: tex.headings, diagnostics: tex.diagnostics });
    resultPort?.postMessage(lastResult);
  }
}

const api = Object.freeze({ update: (data: PreviewUpdate) => render(data) });
Object.defineProperty(window, 'MarknotePreview', { value: api, writable: false, configurable: false });
render({ kind: 'markdown', source: '', theme: 'system' });
