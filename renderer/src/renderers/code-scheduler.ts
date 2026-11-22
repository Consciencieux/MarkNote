import type { CodeJob } from './markdown.ts';

export function createCodeScheduler(makeWorker: () => Worker, apply: (job: CodeJob, html: string) => void): {
  start: (jobs: CodeJob[]) => void; cancel: () => void
} {
  let worker: Worker | undefined;
  function cancel(): void {
    worker?.terminate();
    worker = undefined;
  }
  function start(jobs: CodeJob[]): void {
    cancel();
    if (jobs.length === 0) return;
    let current: Worker;
    try {
      current = makeWorker();
    } catch {
      return;
    }
    worker = current;
    let next = 0;
    current.onmessage = (event: MessageEvent<{ id: number; html: string }>): void => {
      if (worker !== current) return;
      const job = jobs[next];
      if (!job || event.data.id !== job.id || typeof event.data.html !== 'string') {
        cancel();
        return;
      }
      if (event.data.html) apply(job, event.data.html);
      next++;
      if (next < jobs.length) current.postMessage(jobs[next]);
      else cancel();
    };
    current.onerror = () => {
      if (worker === current) cancel();
    };
    current.postMessage(jobs[next]);
  }
  return { start, cancel };
}
