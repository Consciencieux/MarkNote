import mermaid from 'mermaid';
import { previewError, previewText } from '../preview-text.ts';
import { requestsUnsupportedLayout } from './mermaid-block.ts';
import { isolateSvg, sanitizeSvg } from './svg.ts';

const FONT = "system-ui, -apple-system, 'HarmonyOS Sans', sans-serif";

export type PreviewTheme = 'system' | 'light' | 'dark';

let generation = 0;
const sources = new WeakMap<HTMLElement, string>();

export function bindMermaid(root: HTMLElement, diagrams: string[]): void {
  for (const block of root.querySelectorAll<HTMLElement>('.mermaid-block')) {
    const source = diagrams[Number(block.dataset.mnMermaid)];
    if (source !== undefined) sources.set(block, source);
  }
}

/** Drop results from a render that a newer preview update has replaced. */
export function nextMermaidGeneration(): number {
  generation += 1;
  return generation;
}

function diagramTheme(theme: PreviewTheme): 'default' | 'dark' {
  if (theme === 'dark') return 'dark';
  if (theme === 'light') return 'default';
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default';
}

function configure(theme: 'default' | 'dark'): void {
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    htmlLabels: false,
    layout: 'dagre',
    suppressErrorRendering: true,
    fontFamily: FONT,
    theme,
    // A diagram directive must not turn HTML labels back on. The sanitizer
    // removes foreignObject, and that would drop the label text with it.
    secure: ['secure', 'securityLevel', 'startOnLoad', 'maxTextSize', 'suppressErrorRendering', 'maxEdges',
      'htmlLabels'],
    flowchart: { htmlLabels: false },
    sequence: { actorFontFamily: FONT, noteFontFamily: FONT, messageFontFamily: FONT },
    journey: { textPlacement: 'tspan', taskFontFamily: FONT, titleFontFamily: FONT },
    timeline: { textPlacement: 'tspan', taskFontFamily: FONT }
  });
}

function showFailure(block: HTMLElement): void {
  block.innerHTML = previewError(previewText().failed);
}

/** Draw each placeholder from the sources captured by the latest Markdown render. */
export async function paintMermaid(root: ParentNode, theme: PreviewTheme, ticket: number): Promise<void> {
  const blocks = [...root.querySelectorAll<HTMLElement>('.mermaid-block')];
  if (blocks.length === 0) return;
  const palette = diagramTheme(theme);
  configure(palette);
  for (const [index, block] of blocks.entries()) {
    if (ticket !== generation) return;
    const source = sources.get(block);
    if (source === undefined || block.dataset.mnPalette === palette) continue;
    if (requestsUnsupportedLayout(source)) {
      block.dataset.mnPalette = palette;
      showFailure(block);
      continue;
    }
    const id = `mn-mermaid-${ticket}-${index}`;
    try {
      const rendered = await mermaid.render(id, source);
      if (ticket !== generation) return;
      block.dataset.mnPalette = palette;
      block.innerHTML = sanitizeSvg(rendered.svg);
      isolateSvg(block);
    } catch {
      if (ticket !== generation) return;
      block.dataset.mnPalette = palette;
      showFailure(block);
    } finally {
      const leftover = document.getElementById(id);
      if (leftover && !block.contains(leftover)) leftover.remove();
    }
  }
}
