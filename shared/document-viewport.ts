export function applyDocumentViewport(viewport: Record<string, unknown>): boolean {
  const insets = { top: viewport.top, bottom: viewport.bottom };
  if (Object.values(insets).some(value => typeof value !== 'number' || !Number.isFinite(value) || value < 0)) return false;
  for (const [edge, value] of Object.entries(insets)) {
    document.documentElement.style.setProperty(`--inset-${edge}`, `${value}px`);
  }
  return true;
}

export function documentScrollExtent(): number {
  const root = document.scrollingElement;
  return root ? Math.max(0, root.scrollHeight - root.clientHeight) : 0;
}
