import test from 'node:test';
import assert from 'node:assert/strict';
import { safeExternalUrl } from '../src/renderers/external-link.ts';
import { renderMarkdown } from '../src/renderers/markdown.ts';

test('keeps absolute http(s) addresses and encodes non-ascii paths', () => {
  assert.equal(safeExternalUrl('https://example.com/p?a=1&b=2'), 'https://example.com/p?a=1&b=2');
  assert.equal(safeExternalUrl('http://example.com'), 'http://example.com/');
  assert.equal(safeExternalUrl('https://example.com/路径'), 'https://example.com/%E8%B7%AF%E5%BE%84');
});

test('rejects credentials, other schemes, relative paths, missing hosts and overlong addresses', () => {
  const rejected = [
    'https://user:pass@host/',
    'https://user@host/',
    'javascript:alert(1)',
    'data:text/html,hi',
    'file:///tmp/a',
    'content://authority/path',
    'mailto:a@b.c',
    '../doc.md',
    '//host/path',
    '#section',
    'https://',
    `https://example.com/${'a'.repeat(2048)}`
  ];
  for (const value of rejected) assert.equal(safeExternalUrl(value), '', value);
});

test('renders web links as controlled markers and leaves other links as text', () => {
  const html = renderMarkdown([
    '[官网](https://example.com/p?a=1&b=2 "说明")',
    '',
    '[站点](http://example.com)',
    '',
    '<https://example.com/路径>',
    '',
    '[文字][id]',
    '',
    '[id]: https://example.com/a',
    '',
    '[本节](#section)',
    '',
    '[脚本](javascript:alert(1))',
    '',
    '[文件](../doc.md)',
    '',
    '[协议相对](//host/path)',
    '',
    '[凭据](https://user:pass@host/)',
    '',
    '![图](./a.png)'
  ].join('\n'));
  assert.match(html, /data-mn-external-url="https:\/\/example\.com\/p\?a=1&amp;b=2"/);
  assert.match(html, /title="说明"/);
  assert.match(html, /data-mn-external-url="http:\/\/example\.com\/"/);
  assert.match(html, /data-mn-external-url="https:\/\/example\.com\/%E8%B7%AF%E5%BE%84"/);
  assert.match(html, /data-mn-external-url="https:\/\/example\.com\/a"/);
  assert.match(html, /href="#section"/);
  assert.doesNotMatch(html, /href="https?:/);
  assert.match(html, /\[脚本\]\(javascript:alert\(1\)\)/);
  assert.doesNotMatch(html, /<a[^>]*javascript:/);
  assert.doesNotMatch(html, /data-mn-external-url="(?:javascript|data|file|content|mailto|\.\.|\/\/)/);
  assert.doesNotMatch(html, /user:pass/);
  assert.doesNotMatch(html, /<img|\ssrc=/);
});
