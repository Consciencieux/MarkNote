import { StateEffect, StateField, type Extension } from '@codemirror/state';
import { invertedEffects } from '@codemirror/commands';
import type { EditorChangeRange } from '../../shared/editor-protocol.ts';

// The native document stores one mark per separator (n = LF, r = CRLF, c = CR).
// Only mixed documents need this field. CodeMirror owns the edit and its inverse.
export function changedEndings(before?: string, after?: string): EditorChangeRange | undefined {
  if (before === undefined || after === undefined || before === after) return;
  let from = 0;
  let to = before.length;
  let end = after.length;
  while (from < to && from < end && before[from] === after[from]) from++;
  while (to > from && end > from && before[to - 1] === after[end - 1]) {
    to--;
    end--;
  }
  return { from, to, insert: after.slice(from, end) };
}

const restoreEndings = StateEffect.define<EditorChangeRange>();
export const mixedEndings = StateField.define<string>({
  create: () => '',
  update(marks, tr) {
    // Grouped undo applies inverse effects from newest to oldest.
    let restored = false;
    for (const effect of tr.effects) {
      if (effect.is(restoreEndings)) {
        const { from, to, insert } = effect.value;
        marks = marks.slice(0, from) + insert + marks.slice(to);
        restored = true;
      }
    }
    if (restored || !tr.docChanged) return marks;
    const doc = tr.startState.doc;
    const parts: string[] = [];
    let copied = 0;
    tr.changes.iterChanges((from, to, _newFrom, _newTo, inserted) => {
      const start = doc.lineAt(from).number - 1;
      const end = doc.lineAt(to).number - 1;
      if (start === end && inserted.lines === 1) return;
      // A split inherits the current line's terminator, or the preceding one at EOF.
      const style = marks[start] ?? marks[start - 1] ?? 'n';
      parts.push(marks.slice(copied, start), style.repeat(inserted.lines - 1));
      copied = end;
    });
    return parts.length ? parts.join('') + marks.slice(copied) : marks;
  }
});

export function trackMixedEndings(initial: string): Extension {
  return [mixedEndings.init(() => initial), invertedEffects.of(tr => {
    const inverse = changedEndings(tr.state.field(mixedEndings), tr.startState.field(mixedEndings));
    return inverse ? [restoreEndings.of(inverse)] : [];
  })];
}
