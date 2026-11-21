import { renderMarkdownPage, type CodeJob } from './renderers/markdown';
import type { MarkdownPages } from './renderers/markdown-pages';
import { bindMermaid } from './renderers/mermaid';
import { isolateSvg } from './renderers/svg';

/** ArkWeb fits its content. The native Scroll supplies the viewport in CSS pixels. */
export class MarkdownWindow {
  private readonly before = document.createElement('div');
  private readonly after = document.createElement('div');
  private readonly sample = document.createElement('span');
  private readonly mounted = new Map<number, { element: HTMLElement; jobs: CodeJob[] }>();
  private readonly heights: number[] = [];
  private readonly offsets: number[] = [0];
  private width = -1;
  private charWidth = -1;
  private lineHeight = -1;

  constructor(private readonly root: HTMLElement, private readonly markdown: MarkdownPages,
    private readonly sanitize: (html: string) => DocumentFragment) {
    this.sample.className = 'markdown-metrics';
    this.sample.setAttribute('aria-hidden', 'true');
    this.sample.textContent = markdown.source.slice(0, 128).replace(/\s/g, ' ') || 'M';
    this.before.append(this.sample);
    root.replaceChildren(this.before, this.after);
  }

  private locate(y: number): number {
    let low = 0;
    let high = this.heights.length;
    while (low < high) {
      const middle = Math.floor((low + high) / 2);
      if (this.offsets[middle + 1] <= y) low = middle + 1;
      else high = middle;
    }
    return Math.min(low, this.heights.length - 1);
  }

  private measure(): void {
    let dirty = this.heights.length;
    const sample = this.sample.getBoundingClientRect();
    const charWidth = sample.width / this.sample.textContent!.length;
    if (this.width !== this.root.clientWidth || this.charWidth !== charWidth || this.lineHeight !== sample.height) {
      this.width = this.root.clientWidth;
      this.charWidth = charWidth;
      this.lineHeight = sample.height || parseFloat(getComputedStyle(this.root).lineHeight);
      const columns = Math.max(1, this.width / (charWidth || 1));
      for (const [index, page] of this.markdown.pages.entries()) {
        this.heights[index] = this.lineHeight * Math.max(1, page.lines, (page.to - page.from) / columns);
      }
      dirty = 0;
    }
    for (const [index, { element }] of this.mounted) {
      const height = element.getBoundingClientRect().height;
      if (this.heights[index] !== height) {
        this.heights[index] = height;
        dirty = Math.min(dirty, index);
      }
    }
    for (let i = dirty; i < this.heights.length; i++) {
      this.offsets[i + 1] = this.offsets[i] + this.heights[i];
    }
  }

  /** Only rebuild pages entering the reading area. Retained diagrams and images keep their DOM. */
  update(top: number, height: number): boolean {
    this.measure();
    if (!this.heights.length) return false;
    const first = this.locate(Math.max(0, top - height));
    const last = this.locate(top + height * 2);
    let changed = false;
    for (const [index, { element }] of this.mounted) {
      if (index < first || index > last) {
        element.remove();
        this.mounted.delete(index);
        changed = true;
      }
    }
    let next: HTMLElement = this.after;
    for (let index = last; index >= first; index--) {
      let page = this.mounted.get(index);
      if (!page) {
        const rendered = renderMarkdownPage(this.markdown, this.markdown.pages[index]);
        const element = document.createElement('section');
        element.className = 'markdown-page';
        if (index === this.heights.length - 1) element.classList.add('markdown-page-last');
        element.append(this.sanitize(rendered.html));
        this.root.insertBefore(element, next);
        isolateSvg(element, '.svg-canvas svg');
        bindMermaid(element, rendered.diagrams);
        page = { element, jobs: rendered.jobs };
        this.mounted.set(index, page);
        changed = true;
      }
      next = page.element;
    }
    if (changed) this.measure();
    this.before.style.height = `${this.offsets[first]}px`;
    this.after.style.height = `${this.offsets.at(-1)! - this.offsets[last + 1]}px`;
    return changed;
  }

  pendingCode(): CodeJob[] {
    const pending = new Set([...this.root.querySelectorAll<HTMLElement>('code[data-mn-code]')]
      .map(code => Number(code.dataset.mnCode)));
    return [...this.mounted.values()].flatMap(page => page.jobs.filter(job => pending.has(job.id)));
  }
}
