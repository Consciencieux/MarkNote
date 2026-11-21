import type { Env, MarkdownIt, StateBlock, Token } from 'markdown-it';

export interface MarkdownPage {
  from: number;
  to: number;
  lines: number;
  tableHead?: string;
  orderedStart?: number;
  loose?: boolean;
}

export interface MarkdownPages {
  source: string;
  env: Env;
  pages: MarkdownPage[];
}

// Layout targets, not limits on which constructs Markdown can render.
const PAGE_LINES = 32;
const PAGE_CHARS = 4096;
function full(page: MarkdownPage): boolean {
  return page.lines >= PAGE_LINES || page.to - page.from >= PAGE_CHARS;
}

function containerPages(state: StateBlock, root: Token, start: number, end: number): MarkdownPage[] {
  const table = root.tag === 'table';
  const head = table ? state.src.slice(state.bMarks[start], state.bMarks[start + 2]) : undefined;
  const paragraph = state.tokens.find(token => token.type === 'paragraph_open' && token.level === 2);
  const loose = !table && paragraph && !paragraph.hidden;
  const firstNumber = Number(root.attrGet('start') ?? 1);
  const pages: MarkdownPage[] = [];
  let firstLine = start;
  let firstItem = 0;
  let items = 0;
  function finish(next: number): void {
    const page: MarkdownPage = { from: state.bMarks[firstLine], to: state.bMarks[next], lines: next - firstLine };
    if (table && firstLine !== start) page.tableHead = head;
    if (root.tag === 'ol') page.orderedStart = firstNumber + firstItem;
    if (loose) page.loose = true;
    pages.push(page);
    firstItem = items;
    firstLine = next;
  }
  for (const token of state.tokens) {
    if (!token.map) continue;
    const line = token.map[0];
    const item = token.type === 'list_item_open' && token.level === 1;
    const row = table && token.type === 'tr_open' && token.level === 2 && line >= start + 2;
    if (!item && !row) continue;
    if (items > firstItem && (line - firstLine >= PAGE_LINES ||
      state.bMarks[line] - state.bMarks[firstLine] >= PAGE_CHARS)) finish(line);
    items++;
  }
  finish(end);
  return pages;
}

export function indexMarkdown(md: MarkdownIt, input: string): MarkdownPages {
  const source = input.replace(/\r\n?/g, '\n').replace(/\0/g, '\uFFFD');
  const env: Env = {};
  const state = new md.block.State(source, md, env, []);
  const rules = md.block.ruler.getRules('');
  const pages: MarkdownPage[] = [];
  let group: MarkdownPage | undefined;
  function flush(): void {
    if (group) pages.push(group);
    group = undefined;
  }
  // Run each complete top-level block through markdown-it. Its rules own all
  // nested parsing, lookahead, reference definitions and token backpatching.
  // Only their source boundaries survive indexing; inline work is deferred.
  for (let start = state.skipEmptyLines(0); start < state.lineMax; start = state.skipEmptyLines(state.line)) {
    state.line = start;
    state.tokens.length = 0;
    if (!rules.some(rule => rule(state, start, state.lineMax, false)) || state.line <= start) {
      throw new Error('Markdown block did not advance');
    }
    const root = state.tokens[0];
    if (!root || root.type === 'reference_definition') continue;
    const page = { from: state.bMarks[start], to: state.bMarks[state.line], lines: state.line - start };
    if (full(page)) {
      flush();
      if (root.tag === 'ol' || root.tag === 'ul' || root.tag === 'table') {
        for (const section of containerPages(state, root, start, state.line)) pages.push(section);
      } else pages.push(page);
    } else {
      if (group && (full(group) || page.from - group.to > PAGE_CHARS)) flush();
      if (!group) group = page;
      else {
        group.to = page.to;
        group.lines += page.lines;
      }
    }
  }
  flush();
  return { source, env, pages };
}
