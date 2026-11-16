export interface EditorEdit {
  text: string;
  caret: number;
}

/** Prefix whole selected lines; exclude a final line whose first character is not selected. */
export function insertEditorAction(source: string, anchor: number, focus: number,
  id: string, before: string, after: string): EditorEdit {
  const start = Math.max(0, Math.min(source.length, Math.min(anchor, focus)));
  const end = Math.max(start, Math.min(source.length, Math.max(anchor, focus)));
  if (id === 'md-heading' || id === 'md-list' || id === 'md-task') {
    const first = start === 0 ? 0 : source.lastIndexOf('\n', start - 1) + 1;
    const through = end > start && source[end - 1] === '\n' ? end - 1 : end;
    const selected = source.slice(first, through);
    const changed = before + selected.split('\n').join('\n' + before);
    return { text: source.slice(0, first) + changed + source.slice(through),
      caret: first + changed.length };
  }
  if (id === 'md-code-block') {
    // A fence must begin/end on its own line; lengthen it when the selection contains backticks.
    const selected = source.slice(start, end);
    const runs = selected.match(/`+/g) || [];
    let width = 3;
    for (const run of runs) width = Math.max(width, run.length + 1);
    const fence = '`'.repeat(width);
    const prefix = (start > 0 && source[start - 1] !== '\n' ? '\n' : '') + fence + '\n';
    const suffix = '\n' + fence + (end < source.length && source[end] !== '\n' ? '\n' : '');
    return { text: source.slice(0, start) + prefix + selected + suffix + source.slice(end),
      caret: start + prefix.length + selected.length };
  }
  const selected = source.slice(start, end);
  return { text: source.slice(0, start) + before + selected + after + source.slice(end),
    caret: start + before.length + selected.length };
}
