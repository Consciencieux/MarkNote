import test from 'node:test';
import assert from 'node:assert/strict';
import { renderMarkdown } from '../src/renderers/markdown.ts';

test('keeps unavailable images as placeholders without a source address', () => {
  const html = renderMarkdown('![示意图](https://example.com/a.png)\n\n![同目录](./images/a.png)');
  assert.match(html, /class="missing-image image-slot"/);
  assert.match(html, /data-mn-src="https:\/\/example.com\/a.png"/);
  assert.match(html, /data-mn-src="\.\/images\/a.png"/);
  assert.match(html, /\[图片：示意图\]/);
  assert.doesNotMatch(html, /<img/);
  assert.doesNotMatch(html, /\ssrc=/);
});

test('creates image slots for references but not code blocks', () => {
  const source = '![内联](a.png)\n\n![引用][id]\n\n```\n![代码](nope.png)\n```\n\n[id]: images/b.jpg\n\n`![行内代码](code.png)`';
  const html = renderMarkdown(source);
  assert.match(html, /data-mn-src="a\.png"/);
  assert.match(html, /data-mn-src="images\/b\.jpg"/);
  assert.doesNotMatch(html, /data-mn-src="(?:nope|code)\.png"/);
});

test('uses the encoded address markdown-it will render', () => {
  const html = renderMarkdown('![图](图片.png)\n\n![空格](<my pic.png>)');
  assert.match(html, /data-mn-src="%E5%9B%BE%E7%89%87\.png"/);
  assert.match(html, /data-mn-src="my%20pic\.png"/);
});
