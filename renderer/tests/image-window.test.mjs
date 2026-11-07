import test from 'node:test';
import assert from 'node:assert/strict';
import { visibleImageKeys } from '../src/image-window.ts';

test('loads nearby images and can reach images beyond the first 32', () => {
  const images = Array.from({ length: 50 }, (_, i) => ({ key: `${i}.png`, top: i * 1000, bottom: i * 1000 + 200 }));
  assert.deepEqual(visibleImageKeys(images, 40000, 500), ['40.png']);
  assert.deepEqual(visibleImageKeys(images, 0, 500), ['0.png']);
});

test('deduplicates repeated references and ignores empty viewports', () => {
  const images = [{ key: 'a.png', top: 10, bottom: 20 }, { key: 'a.png', top: 30, bottom: 40 }];
  assert.deepEqual(visibleImageKeys(images, 0, 100), ['a.png']);
  assert.deepEqual(visibleImageKeys(images, 0, 0), []);
});
