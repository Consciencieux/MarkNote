import test from 'node:test';
import assert from 'node:assert/strict';
import { createCodeScheduler } from '../src/renderers/code-scheduler.ts';

test('processes blocks sequentially and ignores results from old documents', () => {
  const workers = [];
  const applied = [];
  const scheduler = createCodeScheduler(() => {
    const worker = { sent: [], terminated: false, onmessage: null, onerror: null,
      postMessage(job) { this.sent.push(job); }, terminate() { this.terminated = true; } };
    workers.push(worker);
    return worker;
  }, (job, html) => applied.push([job.id, html]));
  const jobs = [{ id: 0, source: 'a', language: 'js' }, { id: 1, source: 'b', language: 'js' }];
  scheduler.start(jobs);
  const old = workers[0];
  assert.deepEqual(old.sent, [jobs[0]]);
  old.onmessage({ data: { id: 0, html: 'colored a' } });
  assert.deepEqual(old.sent, jobs);
  scheduler.start([{ id: 0, source: 'new', language: 'js' }]);
  assert.equal(old.terminated, true);
  old.onmessage({ data: { id: 1, html: 'stale' } });
  assert.deepEqual(applied, [[0, 'colored a']]);
  workers[1].onmessage({ data: { id: 0, html: 'new' } });
  assert.deepEqual(applied, [[0, 'colored a'], [0, 'new']]);
  assert.equal(workers[1].terminated, true);
});

test('keeps fallback text when a worker cannot be created', () => {
  let calls = 0;
  const scheduler = createCodeScheduler(() => { throw new Error('blocked'); }, () => { calls++; });
  assert.doesNotThrow(() => scheduler.start([{ id: 0, source: 'a', language: 'js' }]));
  assert.equal(calls, 0);
});
