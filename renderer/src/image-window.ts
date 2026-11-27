import { imageLabel, previewText } from './preview-text';
import type { ImageRequest } from './globals';

interface Slot {
  element: HTMLElement;
  image: HTMLImageElement;
  request: ImageRequest;
}

export class PreviewImages {
  private slots = new Map<HTMLElement, Slot>();
  private readonly nearby = new Set<HTMLElement>();
  private targets?: NodeListOf<HTMLElement>;
  private observer?: IntersectionObserver;
  private onChange?: () => void;
  private viewportHeight = -1;
  private nextId = 0;
  private generation = -1;

  observe(root: HTMLElement, onChange: () => void): void {
    this.targets = root.querySelectorAll<HTMLElement>('.image-slot[data-mn-src]');
    this.onChange = onChange;
    this.resize();
  }

  resize(): void {
    const height = window.innerHeight;
    if (!this.targets?.length || height === this.viewportHeight) return;
    this.viewportHeight = height;
    this.observer?.disconnect();
    const observer = new IntersectionObserver(entries => {
      if (this.observer !== observer) return;
      let changed = false;
      for (const entry of entries) {
        const element = entry.target as HTMLElement;
        if (entry.isIntersecting && !this.nearby.has(element)) {
          this.nearby.add(element);
          changed = true;
        } else if (!entry.isIntersecting && this.nearby.delete(element)) {
          changed = true;
        }
      }
      if (changed) this.onChange?.();
    }, { rootMargin: `${height}px 0px` });
    this.observer = observer;
    for (const element of this.targets) observer.observe(element);
  }

  clear(): void {
    this.observer?.disconnect();
    this.observer = undefined;
    this.targets = undefined;
    this.onChange = undefined;
    this.viewportHeight = -1;
    this.nearby.clear();
    this.slots.clear();
  }

  requests(root: HTMLElement, height: number, generation: number): ImageRequest[] | null {
    const next = new Map<HTMLElement, Slot>();
    const ratio = window.devicePixelRatio || 1;
    for (const element of this.nearby) {
      const key = element.dataset.mnSrc;
      if (!key) continue;
      const container = element.closest<HTMLElement>('p,li,td,th,blockquote,h1,h2,h3,h4,h5,h6,figure,section') ?? root;
      const style = getComputedStyle(container);
      const columnWidth = container.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
      const slotWidth = element.clientWidth || columnWidth;
      const widthPx = Math.max(1, Math.ceil(Math.min(slotWidth, columnWidth) * ratio));
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
      const { request, element, image } = slot;
      if (request.id === id) {
        if (!element.style.width) image.style.width = width + 'px';
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
