import { EditorState, Compartment } from '@codemirror/state';
import { EditorView, keymap } from '@codemirror/view';
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands';
import { languageFor } from './languages.js';
import { syntaxTheme } from './syntax-theme.js';
import { EditorSession } from './editor-session.ts';
import { bindSourceScrollbar } from './source-scrollbar.ts';
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
  history(), keymap.of([{ key: 'Mod-f', run: () => session?.requestFind() ?? false },
    ...defaultKeymap, ...historyKeymap]),
  EditorView.scrollMargins.of(() => ({
    top: parseFloat(document.documentElement.style.getPropertyValue('--inset-track-top')) || 0,
    bottom: parseFloat(document.documentElement.style.getPropertyValue('--inset-track-bottom')) || 0
  })),
  EditorView.lineWrapping, languageFor(format), colors.of(syntaxTheme(theme, appearance)),
  editable.of(EditorView.editable.of(true)),
  EditorView.updateListener.of((update) => session?.record(update)),
  EditorState.transactionFilter.of((transaction) => transaction.docChanged && session?.isBlocked() ? [] : transaction)
];
const view = new EditorView({ parent: host, state: EditorState.create({ extensions: extensions('plain', 'off') }) });
bindSourceScrollbar(view.dom, document.querySelector<HTMLInputElement>('#source-scrollbar')!);
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
