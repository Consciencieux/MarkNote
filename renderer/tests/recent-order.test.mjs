import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sortRecentDocuments, updateRecentDocument, removeRecentDocument, toggleFavoriteDocument } from '../../entry/src/main/ets/document/RecentOrder.ts';

const files = [
  { uri: 'a', name: '乙.md', openedAt: 10, modifiedAt: 200 },
  { uri: 'b', name: '甲.tex', openedAt: 20, modifiedAt: 100 },
  { uri: 'c', name: '丙.md', openedAt: 0, modifiedAt: 0 }
];

test('opening a document updates access order without changing modification order', () => {
  const updated = updateRecentDocument(files, 'b', '甲.tex', 30, 100, true);
  assert.deepEqual(sortRecentDocuments(updated, 'modified').map(x => x.uri), ['a', 'b', 'c']);
  assert.deepEqual(sortRecentDocuments(updated, 'opened').map(x => x.uri), ['b', 'a', 'c']);
});

test('opening a document does not move it when modification times are equal', () => {
  const equal = [{ uri: 'a', name: 'a.md', modifiedAt: 100 }, { uri: 'b', name: 'b.md', modifiedAt: 100 }];
  const updated = updateRecentDocument(equal, 'b', 'b.md', 30, 100, true);
  assert.deepEqual(sortRecentDocuments(updated, 'modified').map(x => x.uri), ['a', 'b']);
});

test('saving preserves access time and sorts by the actual modification time', () => {
  const updated = updateRecentDocument(files, 'b', '甲.tex', 30, 300, false);
  assert.equal(updated.find(x => x.uri === 'b').openedAt, 20);
  assert.deepEqual(sortRecentDocuments(updated, 'modified').map(x => x.uri), ['b', 'a', 'c']);
});

test('records with unavailable metadata remain last and legacy records retain their order', () => {
  const old = [{ uri: 'x', name: 'x.md' }, { uri: 'y', name: 'y.md' }];
  assert.deepEqual(sortRecentDocuments(old, 'opened').map(x => x.uri), ['x', 'y']);
  assert.deepEqual(sortRecentDocuments(files, 'modified').map(x => x.uri), ['a', 'b', 'c']);
});

test('name and type ordering is deterministic without mutating input', () => {
  assert.deepEqual(sortRecentDocuments(files, 'type').map(x => x.uri), ['c', 'a', 'b']);
  assert.deepEqual(sortRecentDocuments(files, 'name').map(x => x.name), ['丙.md', '甲.tex', '乙.md'].sort((a,b) => a.localeCompare(b, 'zh-CN', { numeric: true })));
  assert.deepEqual(files.map(x => x.uri), ['a', 'b', 'c']);
});

test('opening more than twelve documents keeps the older records', () => {
  let records = [];
  for (let i = 0; i < 20; i++) records = updateRecentDocument(records, String(i), `${i}.md`, i + 1, 0, true);
  assert.equal(records.length, 20);
  assert.ok(records.some(x => x.uri === '0'));
});

test('Markdown extensions stay together when sorted by type', () => {
  const items = [{ uri: 'a', name: 'a.md' }, { uri: 'b', name: 'b.markdown' }, { uri: 'c', name: 'c.txt' }];
  assert.deepEqual(sortRecentDocuments(items, 'type').map(x => x.uri), ['a', 'b', 'c']);
});

test('removing a recent record retains a favorite and reopening restores its recent status', () => {
  const marked = toggleFavoriteDocument(files, 'b', '甲.tex', 100);
  const removed = removeRecentDocument(marked, 'b', false);
  const saved = removed.find(x => x.uri === 'b');
  assert.equal(saved.favorite, true);
  assert.equal(saved.recent, false);
  const reopened = updateRecentDocument(removed, 'b', '甲.tex', 50, 100, true);
  assert.equal(reopened.find(x => x.uri === 'b').favorite, true);
  assert.equal(reopened.find(x => x.uri === 'b').recent, true);
});

test('unfavoriting a removed history entry clears the record and deleting always clears it', () => {
  const removed = removeRecentDocument(toggleFavoriteDocument(files, 'b', '甲.tex', 100), 'b', false);
  assert.equal(toggleFavoriteDocument(removed, 'b', '甲.tex', 100).some(x => x.uri === 'b'), false);
  assert.equal(removeRecentDocument(removed, 'b', true).some(x => x.uri === 'b'), false);
});
