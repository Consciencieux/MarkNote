import DOMPurify from 'dompurify';
import 'katex/dist/katex.min.css';
import './styles.css';
import { renderMarkdown } from './renderers/markdown';
import { visibleImageKeys } from './image-window';
import { renderPlain } from './renderers/plain';
import { installReferenceHook, sanitizeSvg } from './renderers/svg';
import { renderTexDocument, type TexDocument } from './renderers/tex';
import type { PreviewUpdate } from './globals';
import katex from 'katex';

type Kind = PreviewUpdate['kind'];
let resultPort: MessagePort | undefined;
let lastResult: string | undefined;
let lastRendered: { kind: Kind; source: string; documentId?: number; tex?: TexDocument } | undefined;
window.addEventListener('message', (event: MessageEvent) => {
  if (event.data !== '__marknote_parse_port__' || !event.ports[0]) return;
  resultPort?.close();
  resultPort = event.ports[0];
  if (lastResult) resultPort.postMessage(lastResult);
});

const host = document.getElementById('preview');
if (!host) throw new Error('missing preview root');

function isAppImage(url: string): boolean {
  return /^data:image\/(?:png|jpeg|gif|webp|bmp|svg\+xml);base64,[A-Za-z0-9+/]+={0,2}$/.test(url);
}

let wantedImages = new Set<string>();
function imageWindow(top: number, height: number): string[] {
  if (!host || !Number.isFinite(top) || !Number.isFinite(height) || height <= 0) return [];
  const slots = [...host.querySelectorAll<HTMLElement>('.image-slot')];
  const positions = slots.map(slot => {
    const rect = slot.getBoundingClientRect();
    return { key: slot.dataset.mnSrc ?? '', top: rect.top, bottom: rect.bottom };
  });
  wantedImages = new Set(visibleImageKeys(positions, top, height));
  const pending = new Set<string>();
  for (let index = 0; index < slots.length; index++) {
    const slot = slots[index];
    const position = positions[index];
    const nearby = visibleImageKeys([position], top, height).length > 0;
    slot.dataset.mnNearby = nearby ? '1' : '0';
    const image = slot.querySelector('img');
    if (!nearby && image) {
      slot.style.minHeight = `${slot.getBoundingClientRect().height}px`;
      slot.textContent = `[图片：${slot.dataset.mnAlt || '图片'}]`;
    } else if (nearby && !image && position.key) {
      pending.add(position.key);
    }
  }
  return [...pending];
}

/** Only data received from the application is inserted as an image. */
function setImage(key: string, dataUrl: string): void {
  if (!host || !wantedImages.has(key) || !isAppImage(dataUrl)) return;
  for (const slot of host.querySelectorAll<HTMLElement>('.image-slot')) {
    if (slot.dataset.mnSrc !== key || slot.dataset.mnNearby !== '1' || slot.querySelector('img')) continue;
    const image = document.createElement('img');
    image.alt = slot.dataset.mnAlt || '图片';
    image.src = dataUrl;
    slot.replaceChildren(image);
    slot.classList.add('image-slot-loaded');
    slot.style.minHeight = '';
  }
}

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
  if (lastRendered?.kind === update.kind && lastRendered.source === update.source &&
    lastRendered.documentId === update.documentId) {
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
    lastRendered = { kind: update.kind, source: update.source, documentId: update.documentId };
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
  wantedImages.clear();
  lastRendered = { kind: update.kind, source: update.source, documentId: update.documentId, tex };
  if (tex) {
    for (const element of host!.querySelectorAll<HTMLElement>('.math-inline, .math-display')) {
      katex.render(element.textContent ?? '', element, {
        displayMode: element.classList.contains('math-display'), throwOnError: false,
        trust: false, strict: 'warn', maxSize: 100, maxExpand: 1000, output: 'htmlAndMathml'
      });
    }
    lastResult = JSON.stringify({ kind: 'tex-outline', revision: update.revision,
      headings: tex.headings, diagnostics: tex.diagnostics });
    resultPort?.postMessage(lastResult);
  }
}

const api = Object.freeze({
  update: (data: PreviewUpdate) => render(data),
  imageWindow,
  setImage
});
Object.defineProperty(window, 'MarknotePreview', { value: api, writable: false, configurable: false });
render({ kind: 'markdown', source: '', theme: 'system' });
