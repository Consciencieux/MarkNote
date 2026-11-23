import { EditorState, Compartment, RangeSetBuilder, type SelectionRange } from '@codemirror/state';
import { Decoration, EditorView, keymap, ViewPlugin, type DecorationSet, type ViewUpdate } from '@codemirror/view';
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands';
import { languageFor } from './languages.js';
import { syntaxTheme } from './syntax-theme.js';
import { trackMixedEndings } from './mixed-endings.ts';
import { EditorSession } from './editor-session.ts';
import './production.css';

const host = document.querySelector<HTMLElement>('#editor');
if (!host) throw new Error('Missing editor root');
const editable = new Compartment();
const colors = new Compartment();
const automaticLineDirection = Decoration.line({ attributes: { dir: 'auto' } });
const lineDirections = ViewPlugin.fromClass(class {
  decorations: DecorationSet;

  constructor(view: EditorView) {
    this.decorations = this.build(view);
  }

  update(update: ViewUpdate): void {
    if (update.docChanged || update.viewportChanged) this.decorations = this.build(update.view);
  }

  private build(view: EditorView): DecorationSet {
    // HTML resolves the direction from each rendered line. CodeMirror reads it for bidi movement.
    const ranges = new RangeSetBuilder<Decoration>();
    const doc = view.state.doc;
    let previousStart = -1;
    for (const { from, to } of view.visibleRanges) {
      for (let line = doc.lineAt(from); ; line = doc.line(line.number + 1)) {
        if (line.from > previousStart) {
          // Empty lines inherit the UI direction until they have text.
          if (/\S/.test(line.text)) ranges.add(line.from, line.from, automaticLineDirection);
          previousStart = line.from;
        }
        if (line.to >= to) break;
      }
    }
    return ranges.finish();
  }
}, { decorations: plugin => plugin.decorations });
let session: EditorSession | undefined;
let currentTheme = 'github';
let currentAppearance = 'system';
const media = window.matchMedia('(prefers-color-scheme: dark)');
const resolvedAppearance = (appearance: string) => appearance === 'system' ? (media.matches ? 'dark' : 'light') : appearance;

function selectionOffset(view: EditorView, range: SelectionRange, strategy: string, margin: number): number | undefined {
  const style = document.documentElement.style;
  const visible = window.visualViewport;
  const start = (visible?.offsetTop ?? 0) + (parseFloat(style.getPropertyValue('--inset-top')) || 0);
  const end = (visible?.offsetTop ?? 0) + (visible?.height ?? window.innerHeight) -
    (parseFloat(style.getPropertyValue('--inset-bottom')) || 0);
  if (end <= start) return undefined;

  const caret = view.coordsAtPos(range.head, range.assoc || 1);
  const block = view.lineBlockAt(range.head);
  const top = caret?.top ?? (view.documentTop + block.top);
  const bottom = caret?.bottom ?? (view.documentTop + block.bottom);
  const gap = Math.min(margin, Math.max(0, (end - start - (bottom - top)) / 2));
  let delta = 0;
  if (strategy === 'center') delta = (top + bottom - start - end) / 2;
  else if (strategy === 'start' || (strategy === 'nearest' && top < start + gap)) delta = top - start - gap;
  else if (strategy === 'end' || (strategy === 'nearest' && bottom > end - gap)) delta = bottom - end + gap;
  return delta === 0 ? undefined : window.scrollY + delta;
}

const revealMeasure = {};
const extensions = (format: string, theme: string, appearance: string = 'light') => [
  history(), keymap.of([{ key: 'Mod-f', run: () => session?.requestFind() ?? false },
    ...defaultKeymap, ...historyKeymap]),
  EditorView.scrollHandler.of((view, range, options) => {
    // The scroll hook can run during an editor update. Read coordinates in CodeMirror's read phase.
    view.requestMeasure({ key: revealMeasure,
      read: (measured) => selectionOffset(measured, range, options.y, options.yMargin),
      write: (offset) => { if (offset !== undefined) session?.reportScrollLayout(offset); }
    });
    return true;
  }),
  EditorView.lineWrapping, EditorView.perLineTextDirection.of(true), lineDirections,
  languageFor(format), colors.of(syntaxTheme(theme, appearance)),
  editable.of(EditorView.editable.of(true)),
  EditorView.updateListener.of((update) => session?.record(update)),
  EditorState.transactionFilter.of((transaction) => transaction.docChanged && session?.isBlocked() ? [] : transaction)
];
const view = new EditorView({ parent: host, state: EditorState.create({ extensions: extensions('plain', 'off') }) });
const applyTheme = (theme: string, appearance: string) => {
  currentTheme = theme;
  currentAppearance = appearance;
  view.dispatch({ effects: colors.reconfigure(syntaxTheme(theme, resolvedAppearance(appearance))) });
};
session = new EditorSession(view, editable, (message) => {
  currentTheme = message.theme;
  currentAppearance = message.appearance || 'system';
  return EditorState.create({
    doc: message.source, selection: { anchor: message.anchor, head: message.head },
    extensions: [extensions(message.format, message.theme, resolvedAppearance(currentAppearance)),
      ...(typeof message.lineEndings === 'string' ? [trackMixedEndings(message.lineEndings)] : [])]
  });
}, applyTheme);
new ResizeObserver(() => session?.reportScrollLayout()).observe(view.scrollDOM);
window.addEventListener('resize', () => session?.viewportResized());
window.visualViewport?.addEventListener('resize', () => session?.viewportResized());
media.addEventListener('change', () => {
  if (currentAppearance === 'system') applyTheme(currentTheme, currentAppearance);
});
window.addEventListener('message', (event: MessageEvent) => {
  if (event.data === '__marknote_editor_port__' && event.ports[0]) session?.attach(event.ports[0]);
});
