import { highlightFencedCode } from './code-highlight.ts';
import type { CodeJob } from './markdown.ts';

self.onmessage = (event: MessageEvent<CodeJob>): void => {
  const job = event.data;
  const html = highlightFencedCode(job.source, job.language);
  self.postMessage({ id: job.id, html });
};
