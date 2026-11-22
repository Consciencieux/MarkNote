export function applyDocumentViewport(viewport: Record<string, unknown>): boolean {
  const insets = { top: viewport.top, bottom: viewport.bottom, start: viewport.start, end: viewport.end,
    'track-top': viewport.trackTop, 'track-bottom': viewport.trackBottom };
  if (Object.values(insets).some(value => typeof value !== 'number' || !Number.isFinite(value) || value < 0)) return false;
  for (const [edge, value] of Object.entries(insets)) {
    document.documentElement.style.setProperty(`--inset-${edge}`, `${value}px`);
  }
  return true;
}
