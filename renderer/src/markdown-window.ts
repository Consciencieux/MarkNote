import { renderMarkdownPage, type CodeJob } from './renderers/markdown';
import type { MarkdownPages } from './renderers/markdown-pages';
import { bindMermaid } from './renderers/mermaid';
import { isolateSvg } from './renderers/svg';

type DeferredContent = 'code' | 'images' | 'diagrams';

/** Lay out the text once. Only activate expensive content near the viewport. */
export class MarkdownWindow {
  private readonly codeLanguages = new Map<number, string>();
  private readonly targets = new Map<HTMLElement, DeferredContent>();
  private readonly nearby = {
    code: new Set<HTMLElement>(),
    images: new Set<HTMLElement>(),
    diagrams: new Set<HTMLElement>(),
  };
  private observer?: IntersectionObserver;
  private viewportHeight = -1;

  constructor(root: HTMLElement, markdown: MarkdownPages, sanitize: (html: string) => DocumentFragment,
    private readonly onChange: (changed: ReadonlySet<DeferredContent>) => void) {
    const content = document.createDocumentFragment();
    for (const [index, page] of markdown.pages.entries()) {
      const rendered = renderMarkdownPage(markdown, page);
      const element = document.createElement('section');
      element.className = 'markdown-page';
      if (index === markdown.pages.length - 1) element.classList.add('markdown-page-last');
      element.append(sanitize(rendered.html));
      for (const { id, language } of rendered.jobs) this.codeLanguages.set(id, language);
      bindMermaid(element, rendered.diagrams);
      content.append(element);
    }
    root.replaceChildren(content);
    isolateSvg(root, '.svg-canvas svg');
    this.track(root, 'code[data-mn-code]', 'code');
    this.track(root, '.image-slot', 'images');
    this.track(root, '.mermaid-block', 'diagrams');
    this.resize();
  }

  private track(root: HTMLElement, selector: string, kind: DeferredContent): void {
    for (const element of root.querySelectorAll<HTMLElement>(selector)) this.targets.set(element, kind);
  }

  resize(): void {
    const height = window.innerHeight;
    if (height === this.viewportHeight || this.targets.size === 0) return;
    this.viewportHeight = height;
    this.observer?.disconnect();
    // Keep one viewport of lookahead on each side, including after a window resize.
    const observer = new IntersectionObserver(entries => {
      if (this.observer !== observer) return;
      const changed = new Set<DeferredContent>();
      for (const entry of entries) {
        const element = entry.target as HTMLElement;
        const kind = this.targets.get(element)!;
        const items = this.nearby[kind];
        if (entry.isIntersecting && !items.has(element)) {
          items.add(element);
          changed.add(kind);
        } else if (!entry.isIntersecting && items.delete(element)) {
          changed.add(kind);
        }
      }
      if (changed.size) this.onChange(changed);
    }, { rootMargin: `${height}px 0px` });
    this.observer = observer;
    for (const element of this.targets.keys()) observer.observe(element);
  }

  dispose(): void {
    this.observer?.disconnect();
    this.observer = undefined;
  }

  get imageSlots(): ReadonlySet<HTMLElement> { return this.nearby.images; }
  get diagrams(): ReadonlySet<HTMLElement> { return this.nearby.diagrams; }

  pendingCode(): CodeJob[] {
    const jobs: CodeJob[] = [];
    for (const element of this.nearby.code) {
      const id = Number(element.dataset.mnCode);
      const language = this.codeLanguages.get(id);
      if (language) jobs.push({ id, language, source: element.textContent ?? '' });
    }
    return jobs;
  }
}
