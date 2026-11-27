import TikzWorker from './tikz.worker.ts?worker&inline';
import { previewText } from '../preview-text.ts';
import { isolateSvg, sanitizeSvg } from './svg.ts';

interface Picture { block: HTMLElement; source: string }
const MAX_SOURCE_LENGTH = 50_000;
const DRAW_TIMEOUT_MS = 4_000;

function showSource({ block, source }: Picture): void {
  const message = document.createElement('p');
  message.className = 'error';
  message.textContent = previewText().tikzFailed;
  const pre = document.createElement('pre');
  pre.dir = 'ltr';
  const code = document.createElement('code');
  code.textContent = source;
  pre.append(code);
  block.replaceChildren(message, pre);
}

function showPicture(picture: Picture, svg: unknown): void {
  if (typeof svg === 'string') {
    try {
      picture.block.innerHTML = sanitizeSvg(svg);
      const image = picture.block.querySelector('svg');
      if (image) {
        image.setAttribute('aria-label', 'TikZ');
        isolateSvg(picture.block);
        return;
      }
    } catch {
      // Show the source when this image cannot be displayed.
    }
  }
  showSource(picture);
}

/** Start near the reading position and stop all work when this preview is replaced. */
export function paintTikz(root: HTMLElement, sources: string[]): (() => void) | undefined {
  if (sources.length === 0) return;
  const waiting = new Map<Element, Picture>();
  for (const block of root.querySelectorAll<HTMLElement>('.tikz-block[data-mn-tikz]')) {
    const source = sources[Number(block.dataset.mnTikz)];
    if (source !== undefined) waiting.set(block, { block, source });
  }
  if (waiting.size === 0) return;

  const queue: Picture[] = [];
  let observer: IntersectionObserver | undefined;
  let worker: Worker | undefined;
  let pending: Picture | undefined;
  let timer: number | undefined;

  function finish(svg: unknown): void {
    window.clearTimeout(timer);
    if (pending) showPicture(pending, svg);
    pending = undefined;
    drawNext();
  }

  function stopWorker(): void {
    worker?.terminate();
    worker = undefined;
    window.clearTimeout(timer);
  }

  function dispose(): void {
    observer?.disconnect();
    stopWorker();
    pending = undefined;
    queue.length = 0;
    waiting.clear();
  }

  function failCurrent(): void {
    stopWorker();
    finish(null);
  }

  function drawNext(): void {
    if (pending) return;
    const picture = queue.shift();
    if (!picture) return;
    pending = picture;
    if (!worker) {
      try {
        const active = new TikzWorker();
        active.onmessage = (event: MessageEvent): void => {
          if (worker === active) finish(event.data);
        };
        active.onerror = (): void => {
          if (worker === active) failCurrent();
        };
        worker = active;
      } catch {
        for (const unfinished of [picture, ...queue, ...waiting.values()]) showSource(unfinished);
        dispose();
        return;
      }
    }
    try {
      worker.postMessage(picture.source);
      timer = window.setTimeout(failCurrent, DRAW_TIMEOUT_MS);
    } catch {
      failCurrent();
    }
  }

  function queuePicture(block: Element): void {
    const picture = waiting.get(block);
    if (!picture) return;
    waiting.delete(block);
    observer?.unobserve(block);
    if (picture.source.length > MAX_SOURCE_LENGTH) showSource(picture);
    else queue.push(picture);
  }

  if (typeof IntersectionObserver === 'function') {
    observer = new IntersectionObserver(entries => {
      for (const entry of entries) if (entry.isIntersecting) queuePicture(entry.target);
      drawNext();
    }, { rootMargin: '400px 0px' });
    for (const block of waiting.keys()) observer.observe(block);
  } else {
    for (const block of waiting.keys()) queuePicture(block);
    drawNext();
  }
  return dispose;
}
