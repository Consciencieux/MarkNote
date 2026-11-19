import DOMPurify from 'dompurify';
import 'katex/dist/katex.min.css';
import './styles.css';
import { renderMarkdown } from './renderers/markdown';
import { nextMermaidGeneration, paintMermaid, type PreviewTheme } from './renderers/mermaid';
import { visibleImageKeys } from './image-window';
import { renderPlain } from './renderers/plain';
import { installReferenceHook, isolateSvg, refreshIsolatedSvg, sanitizeSvg } from './renderers/svg';
import { renderTexDocument, type TexDocument } from './renderers/tex';
import type { PreviewUpdate } from './globals';
import { encodePreviewLinkRequest } from './preview-link-message';
import { imageLabel, previewText, usePreviewText } from './preview-text';
import katex from 'katex';

type Kind = PreviewUpdate['kind'];
let resultPort: MessagePort | undefined;
let linkTarget: { kind: Kind; revision: number; documentId: number } | undefined;
let lastResult: string | undefined;
let lastRendered: {
  kind: Kind; source: string; documentId?: number; textStamp: string; theme: PreviewTheme; tex?: TexDocument;
} | undefined;
window.addEventListener('message', (event: MessageEvent) => {
  if (event.data !== '__marknote_parse_port__' || !event.ports[0]) return;
  resultPort?.close();
  resultPort = event.ports[0];
  if (lastResult) resultPort.postMessage(lastResult);
});

const host = document.getElementById('preview');
if (!host) throw new Error('missing preview root');

function notePreviewTarget(update: PreviewUpdate): void {
  const revision = update.revision;
  const documentId = update.documentId;
  if (update.kind === 'markdown' && typeof revision === 'number' && Number.isInteger(revision) && revision >= 0 &&
    typeof documentId === 'number' && Number.isInteger(documentId) && documentId >= 0) {
    linkTarget = { kind: update.kind, revision, documentId };
    return;
  }
  linkTarget = undefined;
}

host.addEventListener('click', (event: MouseEvent) => {
  const target = linkTarget;
  const port = resultPort;
  if (!target || target.kind !== 'markdown' || !port) return;
  const origin = event.target instanceof Element ? event.target :
    (event.target instanceof Node ? event.target.parentElement : null);
  const link = origin?.closest('a[data-mn-external-url]');
  if (!link || !host.contains(link)) return;
  event.preventDefault();
  const encoded = encodePreviewLinkRequest(link.getAttribute('data-mn-external-url') ?? '',
    target.revision, target.documentId);
  if (encoded) port.postMessage(encoded);
});

function paintDiagrams(theme: PreviewTheme): void {
  const ticket = nextMermaidGeneration();
  void paintMermaid(host!, theme, ticket);
}

window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
  if (lastRendered?.theme === 'system') {
    refreshIsolatedSvg(host!);
    if (lastRendered.kind === 'markdown') paintDiagrams('system');
  }
});

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
      slot.textContent = imageLabel(slot.dataset.mnAlt || '');
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
    image.alt = slot.dataset.mnAlt || previewText().imageName;
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

function postTexOutline(update: PreviewUpdate, tex: TexDocument): void {
  lastResult = JSON.stringify({
    kind: 'tex-outline', revision: update.revision, documentId: update.documentId,
    headings: tex.headings, diagnostics: tex.diagnostics
  });
  resultPort?.postMessage(lastResult);
}

function render(update: PreviewUpdate): void {
  if (!['system', 'light', 'dark'].includes(update.theme)) return;
  if (!['markdown', 'plain', 'svg', 'tex-math'].includes(update.kind)) return;
  if (typeof update.source !== 'string') return;
  const mode = update.mode === 'outline' ? 'outline' : 'render';
  if (mode === 'outline') {
    if (update.kind !== 'tex-math') return;
    postTexOutline(update, renderTexDocument(update.source, false));
    return;
  }
  notePreviewTarget(update);
  const textStamp = usePreviewText(update.text);
  document.documentElement.lang = previewText().lang;
  document.documentElement.dir = /^(ar|ug)(-|$)/i.test(previewText().lang) ? 'rtl' : 'ltr';
  document.documentElement.removeAttribute('data-theme');
  if (update.theme !== 'system') document.documentElement.dataset.theme = update.theme;
  if (lastRendered && lastRendered.theme !== update.theme) refreshIsolatedSvg(host!);
  // Theme changes only affect CSS, except Mermaid colors, which are baked into the SVG.
  if (lastRendered?.kind === update.kind && lastRendered.source === update.source &&
    lastRendered.documentId === update.documentId && lastRendered.textStamp === textStamp) {
    if (lastRendered.theme !== update.theme && update.kind === 'markdown') paintDiagrams(update.theme);
    lastRendered = { ...lastRendered, theme: update.theme };
    if (lastRendered.tex) {
      postTexOutline(update, lastRendered.tex);
    }
    return;
  }
  if (!DOMPurify.isSupported) {
    host!.textContent = previewText().unsafe;
    return;
  }
  if (!update.source.trim()) {
    nextMermaidGeneration();
    host!.replaceChildren();
    const empty = document.createElement('p');
    empty.className = 'placeholder';
    empty.textContent = previewText().empty;
    host!.append(empty);
    lastRendered = { kind: update.kind, source: update.source, documentId: update.documentId, textStamp,
      theme: update.theme };
    if (update.kind === 'tex-math') {
      lastResult = JSON.stringify({ kind: 'tex-outline', revision: update.revision, documentId: update.documentId,
        headings: [], diagnostics: [] });
      resultPort?.postMessage(lastResult);
    }
    return;
  }
  installReferenceHook();
  let tex: TexDocument | undefined;
  let html: string;
  try {
    tex = update.kind === 'tex-math' ? renderTexDocument(update.source, true) : undefined;
    html = tex ? tex.html : renderBody(update.kind, update.source);
  } catch {
    linkTarget = undefined;
    nextMermaidGeneration();
    lastRendered = undefined;
    host!.textContent = previewText().failed;
    return;
  }
  host!.innerHTML = DOMPurify.sanitize(html, {
    USE_PROFILES: { html: true, svg: true, svgFilters: true, mathMl: true },
    FORBID_TAGS: ['script', 'iframe', 'object', 'embed', 'foreignObject', 'video', 'audio', 'form'],
    FORBID_ATTR: ['src', 'srcset', 'target', 'formaction'],
    SANITIZE_NAMED_PROPS: false
  });
  isolateSvg(host!, '.svg-canvas svg');
  wantedImages.clear();
  lastRendered = { kind: update.kind, source: update.source, documentId: update.documentId, textStamp,
    theme: update.theme, tex };
  if (update.kind === 'markdown') paintDiagrams(update.theme);
  if (tex) {
    for (const element of host!.querySelectorAll<HTMLElement>('.math-inline, .math-display')) {
      katex.render(element.textContent ?? '', element, {
        displayMode: element.classList.contains('math-display'), throwOnError: false,
        trust: false, strict: 'warn', maxSize: 100, maxExpand: 1000, output: 'htmlAndMathml'
      });
    }
    postTexOutline(update, tex);
  }
}

const api = Object.freeze({
  update: (data: PreviewUpdate) => render(data),
  imageWindow,
  setImage
});
Object.defineProperty(window, 'MarknotePreview', { value: api, writable: false, configurable: false });
