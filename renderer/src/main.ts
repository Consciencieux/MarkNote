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
import { paintTikz } from './renderers/tikz-preview';
import type { ImageRequest, PreviewUpdate } from './globals';
import { encodePreviewLinkRequest } from './preview-link-message';
import { previewText, usePreviewText } from './preview-text';
import katex from 'katex';
import { syntaxColors } from '../../shared/syntax-colors.ts';
import { applyDocumentViewport, documentScrollExtent } from '../../shared/document-viewport.ts';

type Kind = PreviewUpdate['kind'];
let resultPort: MessagePort | undefined;
let renderTarget: { kind: Kind; revision: number; documentId: number } | undefined;
let lastResult: string | undefined;
let scrollLayout: { extent: number; offset: number } | undefined;
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
  reportScrollLayout(0);
});

const host = document.getElementById('preview');
if (!host) throw new Error('missing preview root');

function notePreviewTarget(update: PreviewUpdate): void {
  const revision = update.revision;
  const documentId = update.documentId;
  if (typeof revision === 'number' && Number.isInteger(revision) && revision >= 0 &&
    typeof documentId === 'number' && Number.isInteger(documentId) && documentId >= 0) {
    renderTarget = { kind: update.kind, revision, documentId };
    return;
  }
  renderTarget = undefined;
}

host.addEventListener('click', (event: MouseEvent) => {
  const target = renderTarget;
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
      await paintMermaid(markdown?.diagrams ?? [], theme, ticket);
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
let disposeTikz: (() => void) | undefined;
let renderedDocumentId: number | undefined;

function clearRender(): void {
  cancelCodeHighlight();
  nextMermaidGeneration();
  queuedDiagrams = undefined;
  images.clear();
  markdown?.dispose();
  markdown = undefined;
  disposeTikz?.();
  disposeTikz = undefined;
  scrollLayout = undefined;
  lastRendered = undefined;
  lastResult = undefined;
  host!.replaceChildren();
}

function releasePreview(): void {
  renderTarget = undefined;
  // Retain the page scroll offset while the hidden DOM is released.
  if (host!.firstChild) host!.style.minHeight = `${host!.offsetHeight}px`;
  clearRender();
}

function imageWindow(generation: number): ImageRequest[] | null {
  if (!lastRendered || window.innerHeight <= 0) return [];
  return images.requests(host!, window.innerHeight, generation);
}

function reportScrollLayout(offset?: number, force = false): void {
  if (!renderTarget || !resultPort) return;
  const extent = documentScrollExtent();
  const webOffset = window.scrollY;
  const previous = scrollLayout;
  if (!force && offset === undefined && previous?.extent === extent) return;
  // The browser can move the reading position when a real layout change resizes the page.
  // Include its old position so ArkUI can discard a correction superseded by user input.
  let previousOffset: number | undefined;
  if (offset === undefined && previous && previous.extent !== extent && previous.offset !== webOffset) {
    previousOffset = previous.offset;
    offset = webOffset;
  }
  scrollLayout = { extent, offset: webOffset };
  resultPort.postMessage(JSON.stringify({ ...renderTarget, kind: 'preview-layout', extent, offset, previousOffset }));
}

// Huawei's "获取网页内容高度" guide recommends notifying the native side from the
// web layout when dynamic content changes, after the Web lifecycle events.
new ResizeObserver(() => reportScrollLayout()).observe(document.body, { box: 'border-box' });
window.addEventListener('resize', () => {
  markdown?.resize();
  images.resize();
  reportScrollLayout();
});
window.addEventListener('scroll', () => {
  if (scrollLayout && scrollLayout.extent === documentScrollExtent()) scrollLayout.offset = window.scrollY;
});

function sanitizedFragment(html: string): DocumentFragment {
  const fragment = DOMPurify.sanitize(html, {
    USE_PROFILES: { html: true, svg: true, svgFilters: true, mathMl: true },
    FORBID_TAGS: ['script', 'iframe', 'object', 'embed', 'foreignObject', 'video', 'audio', 'form'],
    FORBID_ATTR: ['src', 'srcset', 'target', 'formaction'],
    SANITIZE_NAMED_PROPS: false,
    RETURN_DOM_FRAGMENT: true
  });
  // User text can have a different base direction in each paragraph.
  // https://www.w3.org/International/questions/qa-html-dir#dirauto
  for (const block of fragment.querySelectorAll('p,h1,h2,h3,h4,h5,h6,li,dt,dd,td,th,pre.plain')) {
    if (!block.hasAttribute('dir')) block.setAttribute('dir', 'auto');
  }
  return fragment;
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
  renderedDocumentId = update.documentId;
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
      markdown = new MarkdownWindow(host!, markdownPages(update.source), sanitizedFragment, changed => {
        if (!markdown || !lastRendered) return;
        if (changed.has('code')) paintCodeHighlight(host!, markdown.pendingCode());
        if (changed.has('diagrams')) paintDiagrams(lastRendered.theme);
      });
    } else {
      tex = update.kind === 'tex-math' ? renderTexDocument(update.source, true) : undefined;
      host!.append(sanitizedFragment(tex ? tex.html : renderBody(update.kind, update.source)));
      isolateSvg(host!, '.svg-canvas svg');
    }
  } catch {
    clearRender();
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
    disposeTikz = paintTikz(host!, tex.tikzPictures);
    postTexOutline(update, tex);
  }
  if (tex || markdown) {
    images.observe(host!, () => {
      if (renderTarget) resultPort?.postMessage(JSON.stringify({ ...renderTarget, kind: 'preview-images' }));
    });
  }
}

const api = Object.freeze({
  update: (data: PreviewUpdate) => {
    const previous = renderedDocumentId;
    render(data);
    if (data.mode !== 'outline') reportScrollLayout(previous === renderedDocumentId ? undefined : 0, true);
  },
  release: releasePreview,
  setViewport: (viewport: Record<string, unknown>) => {
    const applied = applyDocumentViewport(viewport);
    if (applied) reportScrollLayout();
    return applied;
  },
  imageWindow,
  loadImages: (generation: number) => images.load(generation),
  sizeImage: (id: number, width: number, height: number) => images.size(id, width, height)
});
Object.defineProperty(window, 'MarknotePreview', { value: api, writable: false, configurable: false });
