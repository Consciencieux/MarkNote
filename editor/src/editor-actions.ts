import type { Text } from '@codemirror/state';

export interface EditorEdit {
  changes: { from: number; to: number; insert: string };
  caret: number;
}

/** Return one local transaction, excluding a final unselected line. */
export function insertEditorAction(source: Text, anchor: number, focus: number,
  id: string, before: string, after: string): EditorEdit {
  const start = Math.max(0, Math.min(source.length, Math.min(anchor, focus)));
  const end = Math.max(start, Math.min(source.length, Math.max(anchor, focus)));
  if (id === 'md-heading' || id === 'md-list' || id === 'md-task') {
    const first = source.lineAt(start).from;
    const through = end > start && source.sliceString(end - 1, end) === '\n' ? end - 1 : end;
    const selected = source.sliceString(first, through);
    const insert = before + selected.split('\n').join('\n' + before);
    return { changes: { from: first, to: through, insert }, caret: first + insert.length };
  }
  const selected = source.sliceString(start, end);
  if (id === 'md-code-block') {
    const runs = selected.match(/`+/g) || [];
    let width = 3;
    for (const run of runs) width = Math.max(width, run.length + 1);
    const fence = '`'.repeat(width);
    const prefix = (start > 0 && source.sliceString(start - 1, start) !== '\n' ? '\n' : '') + fence + '\n';
    const suffix = '\n' + fence + (end < source.length && source.sliceString(end, end + 1) !== '\n' ? '\n' : '');
    return { changes: { from: start, to: end, insert: prefix + selected + suffix },
      caret: start + prefix.length + selected.length };
  }
  return { changes: { from: start, to: end, insert: before + selected + after },
    caret: start + before.length + selected.length };
}
