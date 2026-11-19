import test from 'node:test';
import assert from 'node:assert/strict';
import { EditorChangeQueue } from '../src/bridge.ts';

function change(text) { return [{ from: 0, to: 0, insert: text }]; }
function ack(sequence, revision) { return { type: 'ack', sessionId: 'doc', epoch: 1, sequence, revision }; }

test('queues successive edits and only resolves save barrier after cumulative acknowledgement', async () => {
  const sent = [];
  const queue = new EditorChangeQueue('doc', 1, 10, (message) => sent.push(message));
  queue.submit(change('a'), { anchor: 1, head: 1 });
  queue.submit(change('b'), { anchor: 1, head: 1 });
  assert.deepEqual(sent.map((item) => [item.sequence, item.baseRevision]), [[1, 10], [2, 11]]);
  let ready = false;
  const barrier = queue.whenSynced().then(() => { ready = true; });
  queue.acknowledge(ack(1, 11));
  await Promise.resolve();
  assert.equal(ready, false);
  queue.acknowledge(ack(2, 12));
  await barrier;
  assert.equal(ready, true);
  assert.equal(queue.pendingCount(), 0);
});

test('ignores stale and impossible acknowledgements and supports retransmission', () => {
  const sent = [];
  const queue = new EditorChangeQueue('doc', 1, 0, (message) => sent.push(message));
  queue.submit(change('a'), { anchor: 1, head: 1 });
  assert.equal(queue.acknowledge({ ...ack(1, 1), sessionId: 'old' }), false);
  assert.equal(queue.acknowledge(ack(2, 2)), false);
  assert.equal(queue.acknowledge(ack(1, 99)), false);
  assert.equal(queue.pendingCount(), 1);
  queue.retransmit();
  assert.deepEqual(sent[0], sent[1]);
  assert.equal(queue.acknowledge(ack(1, 1)), true);
  assert.equal(queue.pendingCount(), 0);
});

test('conflict rejects the save barrier and retains unconfirmed edits', async () => {
  const queue = new EditorChangeQueue('doc', 1, 0, () => {});
  queue.submit(change('a'), { anchor: 1, head: 1 });
  const barrier = queue.whenSynced();
  queue.conflict({ type: 'conflict', sessionId: 'doc', epoch: 1, sequence: 0, revision: 0, reason: 'revision-mismatch' });
  await assert.rejects(barrier, /conflict/);
  assert.equal(queue.pendingCount(), 1);
  assert.throws(() => queue.submit(change('b'), { anchor: 1, head: 1 }), /conflict/);
});

test('buffers new edits after transport failure and retransmits them in order', () => {
  const sent = [];
  let connected = false;
  const queue = new EditorChangeQueue('doc', 1, 0, (message) => {
    if (!connected) throw new Error('disconnected');
    sent.push(message.sequence);
  });
  queue.submit(change('a'), { anchor: 1, head: 1 });
  connected = true;
  queue.submit(change('b'), { anchor: 1, head: 1 });
  assert.deepEqual(sent, []);
  queue.retransmit();
  assert.deepEqual(sent, [1, 2]);
});
