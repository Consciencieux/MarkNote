import DOMPurify from 'dompurify';
import CodeWorker from './code-highlight.worker.ts?worker&inline';
import { createCodeScheduler } from './code-scheduler.ts';
import type { CodeJob } from './markdown.ts';

let host: HTMLElement | undefined;
const scheduler = createCodeScheduler(() => new CodeWorker(), (job, html) => {
  const code = host?.querySelector<HTMLElement>(`code[data-mn-code="${job.id}"]`);
  if (code) code.innerHTML = DOMPurify.sanitize(html, { ALLOWED_TAGS: ['span'], ALLOWED_ATTR: ['class'] });
});

export function cancelCodeHighlight(): void {
  scheduler.cancel();
}

export function paintCodeHighlight(element: HTMLElement, jobs: CodeJob[]): void {
  host = element;
  scheduler.start(jobs);
}
