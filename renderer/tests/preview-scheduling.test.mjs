import test from 'node:test';
import assert from 'node:assert/strict';
import { PreviewDispatch } from '../../entry/src/main/ets/pages/PreviewDispatch.ts';

function command(source) {
  return {
    kind: 'markdown', source, theme: 'system', codeTheme: 'github', revision: 1, documentId: 1, mode: 'render',
    text: {
      lang: 'zh', empty: '', failed: '', unsafe: '', markdownFailed: '', svgUnsafe: '',
      svgInvalid: '', svgRejected: '', mathFailed: '', imageName: '', imageSlot: ''
    }
  };
}

function later() {
  return new Promise((resolve) => setImmediate(resolve));
}

test('a paused preview keeps only the newest request', async () => {
  const sent = [];
  const dispatch = new PreviewDispatch(async (value) => { sent.push(value.source); });
  dispatch.pause();
  dispatch.request(command('a'));
  dispatch.request(command('b'));
  await later();
  assert.deepEqual(sent, []);
  dispatch.resume();
  await later();
  assert.deepEqual(sent, ['b']);
});

test('a queued preview update retains the latest syntax theme', async () => {
  const sent = [];
  const dispatch = new PreviewDispatch(async (value) => { sent.push(value.codeTheme); });
  dispatch.pause();
  dispatch.request({ ...command('text'), codeTheme: 'github' });
  dispatch.request({ ...command('text'), codeTheme: 'atom' });
  dispatch.resume();
  await later();
  assert.deepEqual(sent, ['atom']);
});

test('an in-flight send keeps only the newest follow-up', async () => {
  const sent = [];
  let release = () => {};
  const gate = new Promise((resolve) => { release = resolve; });
  const dispatch = new PreviewDispatch(async (value) => {
    sent.push(value.source);
    if (sent.length === 1) await gate;
  });
  dispatch.request(command('a'));
  await later();
  dispatch.request(command('b'));
  dispatch.request(command('c'));
  assert.deepEqual(sent, ['a']);
  release();
  await later();
  await later();
  assert.deepEqual(sent, ['a', 'c']);
});

test('a failed send can continue and dispose drops later requests', async () => {
  const sent = [];
  let fail = true;
  const dispatch = new PreviewDispatch(async (value) => {
    if (fail) {
      fail = false;
      throw new Error('send failed');
    }
    sent.push(value.source);
  });
  dispatch.request(command('a'));
  dispatch.request(command('b'));
  await later();
  await later();
  assert.deepEqual(sent, ['b']);
  dispatch.dispose();
  dispatch.request(command('c'));
  dispatch.resume();
  await later();
  assert.deepEqual(sent, ['b']);
});
