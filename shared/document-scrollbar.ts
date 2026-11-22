/** ArkWeb scrolls the whole immersive surface. Place its navigation control in the readable part of the pane. */
export function bindDocumentScrollbar(content: HTMLElement, targetId: string): HTMLInputElement {
  const page = document.scrollingElement!;
  const rail = document.createElement('div');
  rail.className = 'document-scrollbar';
  const control = document.createElement('input');
  control.id = 'document-scrollbar';
  control.type = 'range';
  control.min = '0';
  control.max = '0';
  control.step = 'any';
  control.setAttribute('role', 'scrollbar');
  control.setAttribute('aria-controls', targetId);
  control.setAttribute('aria-orientation', 'vertical');
  rail.append(control);
  document.body.append(rail);
  let idleTimer = 0;
  let travel = 0;

  function reveal(): void {
    if (rail.hidden) return;
    rail.setAttribute('data-visible', '');
    window.clearTimeout(idleTimer);
    idleTimer = window.setTimeout(() => rail.removeAttribute('data-visible'), 2000);
  }

  function updatePosition(): void {
    control.valueAsNumber = page.scrollTop;
    rail.style.setProperty('--thumb-offset', `${travel * control.valueAsNumber / Number(control.max)}px`);
    reveal();
  }

  function updateRange(): void {
    const extent = Math.max(0, page.scrollHeight - page.clientHeight);
    rail.hidden = extent === 0;
    if (rail.hidden) return;
    control.max = String(extent);
    const track = rail.clientHeight;
    const thumb = Math.min(track, Math.max(48, track * track / (track + extent)));
    travel = track - thumb;
    rail.style.setProperty('--thumb-height', `${thumb}px`);
    updatePosition();
  }

  const observer = new ResizeObserver(updateRange);
  observer.observe(content);
  observer.observe(rail);
  observer.observe(document.documentElement);
  document.addEventListener('scroll', () => { if (!rail.hidden) updatePosition(); }, { passive: true });
  control.addEventListener('input', () => { page.scrollTop = control.valueAsNumber; });
  control.addEventListener('pointerdown', reveal);
  updateRange();
  return control;
}
