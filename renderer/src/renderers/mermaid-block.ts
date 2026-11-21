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
