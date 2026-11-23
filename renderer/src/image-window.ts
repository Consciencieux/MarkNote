import { imageLabel, previewText } from './preview-text';
import type { ImageRequest } from './globals';

interface Slot {
  element: HTMLElement;
  image: HTMLImageElement;
  request: ImageRequest;
}

export class PreviewImages {
  private slots = new Map<HTMLElement, Slot>();
  private nextId = 0;
  private generation = -1;

  clear(): void {
    this.slots.clear();
  }

  requests(root: HTMLElement, nearby: ReadonlySet<HTMLElement>, height: number, generation: number): ImageRequest[] | null {
    const next = new Map<HTMLElement, Slot>();
    const ratio = window.devicePixelRatio || 1;
    for (const element of nearby) {
      const key = element.dataset.mnSrc;
      if (!key) continue;
      const container = element.closest<HTMLElement>('p,li,td,th,blockquote,h1,h2,h3,h4,h5,h6,section') ?? root;
      const style = getComputedStyle(container);
      const widthPx = Math.max(1, Math.ceil((container.clientWidth - parseFloat(style.paddingLeft) -
        parseFloat(style.paddingRight)) * ratio));
      const heightPx = Math.ceil(height * ratio);
      let slot = this.slots.get(element);
      if (!slot || this.generation !== generation || slot.request.widthPx < widthPx || slot.request.heightPx < heightPx) {
        const image = document.createElement('img');
        image.alt = element.dataset.mnAlt || previewText().imageName;
        slot = { element, image, request: { id: ++this.nextId, key, widthPx, heightPx } };
      }
      next.set(element, slot);
    }
    const changed = generation !== this.generation || this.slots.size !== next.size ||
      Array.from(next.entries()).some(([element, slot]) => this.slots.get(element) !== slot);
    for (const element of this.slots.keys()) {
      if (!next.has(element) && element.classList.contains('image-slot-loaded')) {
        element.style.minHeight = `${element.getBoundingClientRect().height}px`;
        element.textContent = imageLabel(element.dataset.mnAlt || '');
      }
    }
    this.slots = next;
    this.generation = generation;
    return changed ? Array.from(next.values(), slot => slot.request) : null;
  }

  load(generation: number): void {
    if (this.generation !== generation) return;
    for (const slot of this.slots.values()) {
      const { element, image, request } = slot;
      if (image.hasAttribute('src')) continue;
      image.onload = () => this.show(slot);
      image.onerror = () => {
        if (this.slots.get(element) === slot && element.contains(image)) {
          element.style.minHeight = `${element.getBoundingClientRect().height}px`;
          element.textContent = imageLabel(element.dataset.mnAlt || '');
        }
      };
      // Keep the placeholder until native image metadata arrives or the Web image is ready.
      image.src = `https://images.marknote.invalid/${generation}/${request.id}`;
    }
  }

  size(id: number, width: number, height: number): void {
    for (const slot of this.slots.values()) {
      const { request, image } = slot;
      if (request.id === id) {
        image.style.width = `${width}px`;
        image.style.aspectRatio = `${width} / ${height}`;
        this.show(slot);
        return;
      }
    }
  }

  private show(slot: Slot): void {
    const { element, image } = slot;
    if (this.slots.get(element) !== slot || element.contains(image)) return;
    element.replaceChildren(image);
    element.classList.add('image-slot-loaded');
    element.style.minHeight = '';
  }
}
