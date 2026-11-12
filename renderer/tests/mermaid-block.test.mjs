import test from 'node:test';
import assert from 'node:assert/strict';
import { requestsUnsupportedLayout } from '../src/renderers/mermaid-block.ts';

test('rejects an ELK layout request and keeps an ordinary flowchart', () => {
  assert.equal(requestsUnsupportedLayout('flowchart LR\n  A-->B'), false);
  assert.equal(requestsUnsupportedLayout('flowchart-elk LR\n  A-->B'), true);
  assert.equal(requestsUnsupportedLayout('---\nconfig:\n  layout: elk\n---\nflowchart LR\n  A-->B'), true);
  assert.equal(requestsUnsupportedLayout('%%{init: {"layout": "elk"}}%%\nflowchart LR\n  A-->B'), true);
  assert.equal(requestsUnsupportedLayout('%%{init: {"flowchart": {"defaultRenderer": "elk"}}}%%\nflowchart LR\n  A-->B'), true);
  assert.equal(requestsUnsupportedLayout('flowchart LR\n  elk[layout engine]'), false);
});
