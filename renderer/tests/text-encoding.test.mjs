import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as nodeModule from 'node:module';
import vm from 'node:vm';

const needsStripper = { skip: typeof nodeModule.stripTypeScriptTypes !== 'function' };
function encoding() {
  const source = readFileSync(new URL('../../entry/src/main/ets/document/TextEncoding.ets', import.meta.url), 'utf8')
    .replace(/^import .*;\s*$/gm, '').replace(/^export /gm, '');
  const util = { TextDecoder: { create: (name, options) => {
    const decoder = new TextDecoder(name, options);
    return { decodeToString: bytes => decoder.decode(bytes) };
  } } };
  return vm.runInNewContext(`${nodeModule.stripTypeScriptTypes(source)}\nTextEncoding`,
    { util, Uint8Array, Error });
}

test('decodes a large LF document without changing its content', needsStripper, () => {
  const text = '一行测试\n'.repeat(100000);
  const result = encoding().decode(new TextEncoder().encode(text));
  assert.equal(result.text, text);
  assert.equal(result.newline, '\n');
  assert.equal(result.lineEndings, '');
});

test('preserves mixed newline information during decoding', needsStripper, () => {
  const result = encoding().decode(new TextEncoder().encode('one\r\ntwo\nthree\rfour'));
  assert.equal(result.text, 'one\ntwo\nthree\nfour');
  assert.equal(result.newline, 'mixed');
  assert.equal(result.lineEndings, 'rnr');
});
