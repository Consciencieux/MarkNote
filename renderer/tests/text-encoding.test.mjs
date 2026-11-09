import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as nodeModule from 'node:module';
import vm from 'node:vm';

const needsStripper = { skip: typeof nodeModule.stripTypeScriptTypes !== 'function' };
function encoding() {
  const source = readFileSync(new URL('../../entry/src/main/ets/document/TextEncoding.ets', import.meta.url), 'utf8')
    .replace(/^import .*;\s*$/gm, '').replace(/^export /gm, '');
  const util = {
  TextDecoder: { create: (name, options) => {
    const decoder = new TextDecoder(name, options);
    return { decodeToString: bytes => decoder.decode(bytes) };
  } },
  TextEncoder: { create: () => ({ encodeInto: value => new TextEncoder().encode(value) }) }
};
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
  assert.equal(result.lineEndings, 'rnc');
});

test('round-trips LF, CR and CRLF without changing bytes', needsStripper, () => {
  const samples = ['a\nb\nc', 'a\rb\rc', 'a\r\nb\r\nc', 'one\r\ntwo\nthree\rfour'];
  for (const sample of samples) {
    const bytes = new TextEncoder().encode(sample);
    const decoded = encoding().decode(bytes);
    const encoded = encoding().encode(decoded.text, {
      encoding: decoded.encoding,
      newline: decoded.newline,
      lineEndings: decoded.lineEndings,
      hasBom: decoded.hasBom
    });
    assert.equal(new TextDecoder().decode(encoded.bytes), sample);
  }
});
