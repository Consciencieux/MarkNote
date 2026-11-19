import { EditorState, Compartment } from '@codemirror/state';
import { EditorView, keymap } from '@codemirror/view';
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands';
import { searchKeymap } from '@codemirror/search';
import { languageFor } from './languages.js';
import { syntaxTheme } from './syntax-theme.js';
import { EditorSession } from './editor-session.ts';
import './production.css';

const host = document.querySelector<HTMLElement>('#editor');
if (!host) throw new Error('Missing editor root');
const editable = new Compartment();
const colors = new Compartment();
let session: EditorSession | undefined;
let currentTheme = 'github';
let currentAppearance = 'system';
const media = window.matchMedia('(prefers-color-scheme: dark)');
const resolvedAppearance = (appearance: string) => appearance === 'system' ? (media.matches ? 'dark' : 'light') : appearance;
const extensions = (format: string, theme: string, appearance: string = 'light') => [
  history(), keymap.of([...defaultKeymap, ...historyKeymap, ...searchKeymap]),
  EditorView.lineWrapping, languageFor(format), colors.of(syntaxTheme(theme, appearance)),
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
    extensions: extensions(message.format, message.theme, resolvedAppearance(currentAppearance))
  });
}, applyTheme);
media.addEventListener('change', () => {
  if (currentAppearance === 'system') applyTheme(currentTheme, currentAppearance);
});
window.addEventListener('message', (event: MessageEvent) => {
  if (event.data === '__marknote_editor_port__' && event.ports[0]) session?.attach(event.ports[0]);
});
