import test from 'node:test';
import assert from 'node:assert/strict';
import { loadArktsModules } from './helpers/arkts-loader.mjs';

function clock() {
  const timers = [];
  let now = 0;
  let sequence = 1;
  return {
    setTimeout(fn, ms) {
      const id = sequence++;
      timers.push({ id, fn, at: now + ms });
      return id;
    },
    clearTimeout(id) {
      const index = timers.findIndex((item) => item.id === id);
      if (index >= 0) timers.splice(index, 1);
    },
    advance(ms) {
      now += ms;
      let fired = true;
      while (fired) {
        fired = false;
        const due = timers.filter((item) => item.at <= now).sort((left, right) => left.at - right.at);
        if (due.length === 0) return;
        const item = due[0];
        const index = timers.indexOf(item);
        if (index < 0) continue;
        timers.splice(index, 1);
        item.fn();
        fired = true;
      }
    }
  };
}

function request(Request, revision, query, outline, count) {
  const item = new Request();
  item.sessionId = 1;
  item.revision = revision;
  item.source = '# Title\n\nbody';
  item.formatId = 'markdown';
  item.query = query;
  item.needOutline = outline;
  item.needCount = count;
  return item;
}

test('continuous edits analyze only the latest request and identical text is not repeated', async () => {
  const time = clock();
  const results = [];
  const api = loadArktsModules(
    ['model/Document.ets', 'document/TextSearch.ets', 'document/DocumentAnalysis.ets'],
    '({ DocumentAnalysis, AnalysisRequest })',
    { ...time, AppText: { text: (name) => String(name) }, $r: (name) => name }
  );
  const analysis = new api.DocumentAnalysis((result) => results.push(result));
  analysis.schedule(request(api.AnalysisRequest, 1, 'body', true, true));
  analysis.schedule(request(api.AnalysisRequest, 2, 'old', true, true));
  analysis.schedule(request(api.AnalysisRequest, 3, 'body', true, true));
  time.advance(119);
  assert.equal(results.length, 0);
  time.advance(1);
  assert.equal(results.length, 1);
  assert.equal(results[0].revision, 3);
  assert.equal(results[0].query, 'body');
  assert.equal(results[0].headings[0].text, 'Title');
  analysis.schedule(request(api.AnalysisRequest, 3, 'body', true, true));
  time.advance(500);
  assert.equal(results.length, 1);
  analysis.schedule(request(api.AnalysisRequest, 4, '', false, false));
  time.advance(500);
  assert.equal(results.length, 1);
});

test('flush returns the current outline without waiting for the timer', async () => {
  const time = clock();
  const api = loadArktsModules(
    ['model/Document.ets', 'document/TextSearch.ets', 'document/DocumentAnalysis.ets'],
    '({ DocumentAnalysis, AnalysisRequest })',
    { ...time, AppText: { text: (name) => String(name) }, $r: (name) => name }
  );
  const analysis = new api.DocumentAnalysis(() => {});
  const result = await analysis.flush(request(api.AnalysisRequest, 4, '', true, false));
  assert.equal(result.headings[0].offset, 0);
  assert.equal(result.headings[0].text, 'Title');
  assert.equal(result.matchCount, null);
});
