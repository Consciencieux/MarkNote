import mermaid from 'mermaid';
import { previewError, previewText } from '../preview-text.ts';
import { mermaidSources, requestsUnsupportedLayout } from './mermaid-block.ts';
import { sanitizeSvg } from './svg.ts';

const FONT = "system-ui, -apple-system, 'HarmonyOS Sans', sans-serif";

export type PreviewTheme = 'system' | 'light' | 'dark';

let generation = 0;

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
  const sources = mermaidSources();
  const blocks = [...root.querySelectorAll<HTMLElement>('.mermaid-block')];
  if (blocks.length === 0) return;
  configure(diagramTheme(theme));
  for (const block of blocks) {
    if (ticket !== generation) return;
    const index = Number(block.dataset.mnMermaid);
    const source = sources[index];
    if (!Number.isInteger(index) || source === undefined) continue;
    if (requestsUnsupportedLayout(source)) {
      showFailure(block);
      continue;
    }
    const id = `mn-mermaid-${ticket}-${index}`;
    try {
      const rendered = await mermaid.render(id, source);
      if (ticket !== generation) return;
      block.innerHTML = sanitizeSvg(rendered.svg);
    } catch {
      if (ticket !== generation) return;
      showFailure(block);
    } finally {
      const leftover = document.getElementById(id);
      if (leftover && !block.contains(leftover)) leftover.remove();
    }
  }
}
