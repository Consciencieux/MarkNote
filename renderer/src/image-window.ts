import { imageLabel, previewText } from './preview-text';
import type { ImageRequest } from './globals';

interface ImageDocument { documentId: number; revision: number }
type ImageControl =
  | ({ kind: 'image-begin'; id: number; request: ImageRequest } & ImageDocument)
  | { kind: 'image-cancel'; id: number }
  | { kind: 'image-finish'; id: number; sequence: number; mime: string; intrinsicWidth: number; intrinsicHeight: number };

interface Transfer extends ImageDocument {
  id: number;
  sequence: number;
  request: ImageRequest;
  parts: ArrayBuffer[];
}

export class PreviewImages {
  private nearby = new Map<HTMLElement, ImageRequest>();
  private loaded = new WeakMap<HTMLElement, ImageRequest>();
  private urls = new Map<HTMLImageElement, string>();
  private transfer?: Transfer;

  private revoke(image: HTMLImageElement): void {
    const url = this.urls.get(image);
    if (url) URL.revokeObjectURL(url);
    this.urls.delete(image);
  }

  clear(): void {
    this.nearby.clear();
    this.transfer = undefined;
    for (const image of this.urls.keys()) this.revoke(image);
  }

  requests(root: HTMLElement, top: number, height: number): ImageRequest[] {
    this.nearby.clear();
    for (const image of this.urls.keys()) {
      if (!image.isConnected) this.revoke(image);
    }
    const pending = new Map<string, ImageRequest>();
    const pixelRatio = window.devicePixelRatio || 1;
    for (const slot of root.querySelectorAll<HTMLElement>('.image-slot')) {
      const rect = slot.getBoundingClientRect();
      const image = slot.querySelector('img');
      if (rect.bottom <= Math.max(0, top - height) || rect.top >= top + 2 * height) {
        if (image) {
          this.revoke(image);
          slot.style.minHeight = `${rect.height}px`;
          slot.textContent = imageLabel(slot.dataset.mnAlt || '');
          this.loaded.delete(slot);
        }
        continue;
      }
      const key = slot.dataset.mnSrc;
      if (!key) continue;
      const container = slot.closest<HTMLElement>('p,li,td,th,blockquote,h1,h2,h3,h4,h5,h6,section') ?? root;
      const style = getComputedStyle(container);
      const width = container.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
      const request = { key, widthPx: Math.max(1, Math.ceil(width * pixelRatio)), heightPx: Math.ceil(height * pixelRatio) };
      this.nearby.set(slot, request);
      const loaded = this.loaded.get(slot);
      if (loaded && loaded.widthPx >= request.widthPx && loaded.heightPx >= request.heightPx) continue;
      const other = pending.get(key);
      if (other) other.widthPx = Math.max(other.widthPx, request.widthPx);
      else pending.set(key, { ...request });
    }
    return [...pending.values()];
  }

  connect(port: MessagePort, target: () => ImageDocument | undefined): void {
    this.transfer = undefined;
    port.onmessage = (event: MessageEvent<unknown>) => {
      const ack = (id: number, sequence: number, accepted: boolean) =>
        port.postMessage(JSON.stringify({ kind: 'image-ack', id, sequence, accepted }));
      const document = target();
      const transfer = this.transfer;
      const current = transfer && document && document.documentId === transfer.documentId &&
        document.revision === transfer.revision;
      if (event.data instanceof ArrayBuffer) {
        if (!transfer) return;
        if (current) transfer.parts.push(event.data);
        ack(transfer.id, ++transfer.sequence, !!current);
        return;
      }
      if (typeof event.data !== 'string') return;
      const message: ImageControl = JSON.parse(event.data);
      if (message.kind === 'image-begin') {
        const accepted = document?.documentId === message.documentId && document.revision === message.revision &&
          [...this.nearby.values()].some(request => request.key === message.request.key);
        this.transfer = accepted ? { ...message, sequence: 0, parts: [] } : undefined;
        ack(message.id, 0, accepted);
      } else if (message.kind === 'image-cancel') {
        if (transfer?.id === message.id) this.transfer = undefined;
      } else if (message.kind === 'image-finish') {
        if (transfer?.id === message.id) this.transfer = undefined;
        let installed = false;
        try {
          if (current && transfer.id === message.id && message.sequence === transfer.sequence + 1 &&
            /^image\/(?:png|jpeg|gif|webp|bmp|svg\+xml)$/.test(message.mime) && transfer.parts.length > 0) {
            const blob = new Blob(transfer.parts, { type: message.mime });
            this.install(transfer.request, blob, message.intrinsicWidth, message.intrinsicHeight);
            installed = true;
          }
        } finally {
          ack(message.id, message.sequence, installed);
        }
      }
    };
  }

  private install({ key, widthPx, heightPx }: ImageRequest, blob: Blob, intrinsicWidth: number, intrinsicHeight: number): void {
    for (const [slot, request] of this.nearby) {
      if (!slot.isConnected || request.key !== key) continue;
      const loaded = this.loaded.get(slot);
      if (loaded && loaded.widthPx >= request.widthPx && loaded.heightPx >= request.heightPx) continue;
      const old = slot.querySelector('img');
      if (old) this.revoke(old);
      const image = document.createElement('img');
      image.alt = slot.dataset.mnAlt || previewText().imageName;
      if (intrinsicWidth > 0) image.style.width = `${intrinsicWidth}px`;
      if (intrinsicWidth > 0 && intrinsicHeight > 0) image.style.aspectRatio = `${intrinsicWidth} / ${intrinsicHeight}`;
      const url = URL.createObjectURL(blob);
      this.urls.set(image, url);
      image.onload = () => this.revoke(image);
      image.onerror = () => {
        this.revoke(image);
        if (image.parentElement === slot) slot.textContent = imageLabel(slot.dataset.mnAlt || '');
      };
      image.src = url;
      slot.replaceChildren(image);
      slot.classList.add('image-slot-loaded');
      slot.style.minHeight = '';
      this.loaded.set(slot, { key, widthPx, heightPx });
    }
  }
}
