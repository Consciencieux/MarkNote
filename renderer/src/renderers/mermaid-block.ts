let sources: string[] = [];

/** Start a new Markdown render so diagram indexes match this pass. */
export function beginMermaidDiagrams(): void {
  sources = [];
}

export function mermaidSources(): readonly string[] {
  return sources;
}

/** Keep the diagram source out of the HTML. The index is the only thing the page keeps. */
export function mermaidPlaceholder(source: string): string {
  const index = sources.length;
  sources.push(source);
  return `<section class="mermaid-block" data-mn-mermaid="${index}"></section>`;
}

/**
 * Mermaid 11 draws a flowchart that asks for ELK with Dagre instead of failing.
 * Other unknown layouts throw. Both cases stay unsupported here.
 */
export function requestsUnsupportedLayout(source: string): boolean {
  return /(?:^|\n)\s*layout\s*:\s*["']?elk\b/i.test(source) ||
    /flowchart-elk\b/i.test(source) ||
    /["']layout["']\s*:\s*["']elk\b/i.test(source) ||
    /["']?defaultRenderer["']?\s*:\s*["']elk["']/i.test(source);
}
