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

  requests(root: HTMLElement, top: number, height: number, generation: number): ImageRequest[] | null {
    const next = new Map<HTMLElement, Slot>();
    const ratio = window.devicePixelRatio || 1;
    for (const element of root.querySelectorAll<HTMLElement>('.image-slot')) {
      const rect = element.getBoundingClientRect();
      const key = element.dataset.mnSrc;
      if (!key || rect.bottom <= Math.max(0, top - height) || rect.top >= top + 2 * height) {
        if (this.slots.has(element)) {
          element.style.minHeight = `${rect.height}px`;
          element.textContent = imageLabel(element.dataset.mnAlt || '');
        }
        continue;
      }
      const container = element.closest<HTMLElement>('p,li,td,th,blockquote,h1,h2,h3,h4,h5,h6,section') ?? root;
      const style = getComputedStyle(container);
      const widthPx = Math.max(1, Math.ceil((container.clientWidth - parseFloat(style.paddingLeft) -
        parseFloat(style.paddingRight)) * ratio));
      const heightPx = Math.ceil(height * ratio);
      let slot = this.slots.get(element);
      if (!slot || this.generation !== generation || slot.request.widthPx < widthPx || slot.request.heightPx < heightPx) {
        const image = document.createElement('img');
        image.alt = element.dataset.mnAlt || previewText().imageName;
        image.onerror = () => {
          if (element.contains(image)) element.textContent = imageLabel(element.dataset.mnAlt || '');
        };
        slot = { element, image, request: { id: ++this.nextId, key, widthPx, heightPx } };
      }
      next.set(element, slot);
    }
    const changed = generation !== this.generation || this.slots.size !== next.size ||
      Array.from(next.entries()).some(([element, slot]) => this.slots.get(element) !== slot);
    this.slots = next;
    this.generation = generation;
    return changed ? Array.from(next.values(), slot => slot.request) : null;
  }

  load(generation: number): void {
    if (this.generation !== generation) return;
    for (const { element, image, request } of this.slots.values()) {
      if (image.hasAttribute('src')) continue;
      image.src = `https://images.marknote.invalid/${generation}/${request.id}`;
      element.replaceChildren(image);
      element.classList.add('image-slot-loaded');
      element.style.minHeight = '';
    }
  }

  size(id: number, width: number, height: number): void {
    for (const { request, image } of this.slots.values()) {
      if (request.id === id) {
        image.style.width = `${width}px`;
        image.style.aspectRatio = `${width} / ${height}`;
        return;
      }
    }
  }
}
