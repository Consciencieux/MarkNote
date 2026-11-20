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
    // HarmonyOS ignoreBOM=true removes the leading marker; WHATWG means the reverse.
    const decoder = new TextDecoder(name, { fatal: options.fatal, ignoreBOM: !options.ignoreBOM });
    return { decodeToString: bytes => decoder.decode(bytes) };
  } },
  TextEncoder: { create: (name) => ({ encodeInto: value => {
    if (name === 'utf-8') return new TextEncoder().encode(value);
    if (name === 'utf-16le' || name === 'utf-16be') {
      const bytes = Buffer.from(value, 'utf16le');
      if (name === 'utf-16be') bytes.swap16();
      return new Uint8Array(bytes);
    }
    if (name === 'gb18030' && value === '中文') return new Uint8Array([0xd6, 0xd0, 0xce, 0xc4]);
    throw new Error(`unsupported test encoding: ${name}`);
  } }) }
};
  return vm.runInNewContext(`${nodeModule.stripTypeScriptTypes(source)}\nTextEncoding`,
    { util, Uint8Array, Error,
      userNotice: (message) => { const error = new Error(message); error.name = 'UserNotice'; return error; } });
}

test('decodes a large LF document without changing its content', needsStripper, () => {
  const text = '一行测试\n'.repeat(100000);
  const result = encoding().decode(new TextEncoder().encode(text));
  assert.equal(result.text, text);
  assert.equal(result.newline, '\n');
  assert.equal(result.lineEndings, '');
});

test('preserves an initial U+FEFF after an actual BOM in UTF-8 and UTF-16', needsStripper, () => {
  const cases = [
    ['utf-8', [0xef, 0xbb, 0xbf, 0xef, 0xbb, 0xbf, 0x41]],
    ['utf-16le', [0xff, 0xfe, 0xff, 0xfe, 0x41, 0x00]],
    ['utf-16be', [0xfe, 0xff, 0xfe, 0xff, 0x00, 0x41]],
  ];
  for (const [name, octets] of cases) {
    const codec = encoding();
    const decoded = codec.decode(new Uint8Array(octets));
    assert.equal(decoded.text, '\uFEFFA', name);
    assert.equal(decoded.encoding, name);
    assert.equal(decoded.hasBom, true);
    assert.deepEqual(Array.from(codec.encode(decoded.text, decoded).bytes), octets, name);
  }
});

test('encodes GB18030 without pretending it is UTF-8', needsStripper, () => {
  const codec = encoding();
  const decoded = codec.decode(new Uint8Array([0xd6, 0xd0, 0xce, 0xc4]));
  assert.equal(decoded.text, '中文');
  assert.equal(decoded.encoding, 'gb18030');
  assert.deepEqual(Array.from(codec.encode(decoded.text, decoded).bytes), [0xd6, 0xd0, 0xce, 0xc4]);
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
