import DOMPurify from 'dompurify';
import 'katex/dist/katex.min.css';
import './styles.css';
import { markdownPages } from './renderers/markdown';
import { MarkdownWindow } from './markdown-window';
import { cancelCodeHighlight, paintCodeHighlight } from './renderers/deferred-code';
import { nextMermaidGeneration, paintMermaid, type PreviewTheme } from './renderers/mermaid';
import { PreviewImages } from './image-window';
import { renderPlain } from './renderers/plain';
import { installReferenceHook, isolateSvg, refreshIsolatedSvg, sanitizeSvg } from './renderers/svg';
import { renderTexDocument, type TexDocument } from './renderers/tex';
import type { ImageRequest, PreviewUpdate } from './globals';
import { encodePreviewLinkRequest } from './preview-link-message';
import { previewText, usePreviewText } from './preview-text';
import katex from 'katex';
import { syntaxColors } from '../../shared/syntax-colors.ts';

type Kind = PreviewUpdate['kind'];
let resultPort: MessagePort | undefined;
let linkTarget: { kind: Kind; revision: number; documentId: number } | undefined;
let lastResult: string | undefined;
let codeTheme = 'github';
let appearance = 'system';
function applyCodeColors(): void {
  const dark = appearance === 'dark' || (appearance === 'system' && window.matchMedia('(prefers-color-scheme: dark)').matches);
  const colors = syntaxColors(codeTheme, dark ? 'dark' : 'light');
  const root = document.documentElement;
  root.dataset.codeTheme = codeTheme;
  for (const [role, color] of Object.entries({ keyword: colors.keyword, string: colors.string,
    number: colors.number, comment: colors.comment, tag: colors.name, attr: colors.name, function: colors.title })) {
    root.style.setProperty(`--hljs-${role}`, color);
  }
}
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

let queuedDiagrams: { theme: PreviewTheme; ticket: number } | undefined;
let drawingDiagrams = false;

async function drawDiagrams(): Promise<void> {
  drawingDiagrams = true;
  try {
    while (queuedDiagrams) {
      const { theme, ticket } = queuedDiagrams;
      queuedDiagrams = undefined;
      await paintMermaid(host!, theme, ticket);
    }
  } finally {
    drawingDiagrams = false;
  }
}

function paintDiagrams(theme: PreviewTheme): void {
  queuedDiagrams = { theme, ticket: nextMermaidGeneration() };
  if (!drawingDiagrams) void drawDiagrams();
}

window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
  if (appearance === 'system') applyCodeColors();
  if (lastRendered?.theme === 'system') {
    refreshIsolatedSvg(host!);
    if (lastRendered.kind === 'markdown') paintDiagrams('system');
  }
});

const images = new PreviewImages();
let markdown: MarkdownWindow | undefined;
let viewport = { top: 0, height: window.screen.height || 800 };

function clearRender(): void {
  cancelCodeHighlight();
  nextMermaidGeneration();
  queuedDiagrams = undefined;
  images.clear();
  markdown = undefined;
  lastRendered = undefined;
  lastResult = undefined;
  host!.replaceChildren();
}

function releasePreview(): void {
  linkTarget = undefined;
  // Retain the native Scroll offset while the hidden DOM is released.
  if (host!.firstChild) host!.style.minHeight = `${host!.offsetHeight}px`;
  clearRender();
}

function updateWindow(theme: PreviewTheme): void {
  if (markdown?.update(viewport.top, viewport.height)) {
    paintCodeHighlight(host!, markdown.pendingCode());
    paintDiagrams(theme);
  }
}

function imageWindow(top: number, height: number, generation: number): ImageRequest[] | null {
  if (!Number.isFinite(top) || !Number.isFinite(height) || height <= 0) return [];
  viewport = { top, height };
  if (!markdown || !lastRendered) return [];
  updateWindow(lastRendered.theme);
  return images.requests(host!, top, height, generation);
}

// Loading an image, drawing a diagram, or resizing a split pane can bring
// different pages and image slots into view without a native scroll gesture.
new ResizeObserver(() => {
  if (markdown && linkTarget) {
    resultPort?.postMessage(JSON.stringify({ ...linkTarget, kind: 'preview-layout' }));
  }
}).observe(host);

function sanitizedFragment(html: string): DocumentFragment {
  return DOMPurify.sanitize(html, {
    USE_PROFILES: { html: true, svg: true, svgFilters: true, mathMl: true },
    FORBID_TAGS: ['script', 'iframe', 'object', 'embed', 'foreignObject', 'video', 'audio', 'form'],
    FORBID_ATTR: ['src', 'srcset', 'target', 'formaction'],
    SANITIZE_NAMED_PROPS: false,
    RETURN_DOM_FRAGMENT: true
  });
}

function renderBody(kind: Kind, source: string): string {
  if (kind === 'svg') return `<section class="svg-canvas">${sanitizeSvg(source)}</section>`;
  return renderPlain(source);
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
  host!.style.minHeight = '';
  codeTheme = ['off', 'github', 'atom', 'vs'].includes(update.codeTheme || '') ? update.codeTheme! : 'github';
  appearance = update.theme;
  applyCodeColors();
  notePreviewTarget(update);
  const textStamp = usePreviewText(update.text);
  document.documentElement.lang = previewText().lang;
  document.documentElement.dir = update.text?.rtl ? 'rtl' : 'ltr';
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
  if (lastRendered && lastRendered.documentId !== update.documentId) viewport.top = 0;
  clearRender();
  if (!DOMPurify.isSupported) {
    host!.textContent = previewText().unsafe;
    return;
  }
  if (!update.source.trim()) {
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
  try {
    if (update.kind === 'markdown') {
      markdown = new MarkdownWindow(host!, markdownPages(update.source), sanitizedFragment);
      updateWindow(update.theme);
    } else {
      tex = update.kind === 'tex-math' ? renderTexDocument(update.source, true) : undefined;
      host!.append(sanitizedFragment(tex ? tex.html : renderBody(update.kind, update.source)));
      isolateSvg(host!, '.svg-canvas svg');
    }
  } catch {
    clearRender();
    linkTarget = undefined;
    host!.textContent = previewText().failed;
    return;
  }
  lastRendered = { kind: update.kind, source: update.source, documentId: update.documentId, textStamp,
    theme: update.theme, tex };
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
  release: releasePreview,
  imageWindow,
  loadImages: (generation: number) => images.load(generation),
  sizeImage: (id: number, width: number, height: number) => images.size(id, width, height)
});
Object.defineProperty(window, 'MarknotePreview', { value: api, writable: false, configurable: false });
