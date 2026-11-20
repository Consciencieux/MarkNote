import { Compartment, EditorState } from '@codemirror/state';
import { EditorView, type ViewUpdate } from '@codemirror/view';
import { redo, undo, undoDepth, redoDepth, isolateHistory } from '@codemirror/commands';
import { insertEditorAction } from './editor-actions.ts';
import type { EditorAck, EditorChangeRange, EditorConflict } from '../../shared/editor-protocol.ts';
import { EditorChangeQueue } from './bridge.ts';

interface InitMessage {
  type: 'init'; sessionId: string; epoch: number; revision: number; source: string;
  format: string; theme: string; appearance?: string; language: string; direction: string; anchor: number; head: number;
}

/** Web-side session. It only exchanges document messages over the transferred port. */
export class EditorSession {
  private view: EditorView;
  private makeState: (message: InitMessage) => EditorState;
  private editable: Compartment;
  private setTheme: ((theme: string, appearance: string) => void) | undefined;
  private port: MessagePort | undefined;
  private queue: EditorChangeQueue | undefined;
  private current: InitMessage | undefined;
  private blocked: boolean = false;
  private suspended: boolean = false;
  private suspendGeneration: number = 0;
  private activeFlushes = new Map<string, AbortController>();

  constructor(view: EditorView, editable: Compartment, makeState: (message: InitMessage) => EditorState,
    setTheme?: (theme: string, appearance: string) => void) {
    this.view = view;
    this.editable = editable;
    this.makeState = makeState;
    this.setTheme = setTheme;
  }

  isBlocked(): boolean { return this.blocked || this.suspended; }

  requestFind(): boolean {
    if (!this.current || !this.port) return false;
    try {
      this.send({ type: 'find-request', sessionId: this.current.sessionId, epoch: this.current.epoch });
      return true;
    } catch { return false; }
  }

  attach(port: MessagePort): void {
    for (const controller of this.activeFlushes.values()) controller.abort();
    if (this.suspended && !this.blocked) {
      this.suspended = false;
      this.view.dispatch({ effects: this.editable.reconfigure(EditorView.editable.of(true)) });
    }
    this.port?.close();
    this.port = port;
    port.onmessage = (event: MessageEvent): void => this.receive(event.data);
    port.start();
    this.send({ type: 'ready' });
    this.queue?.retransmit();
  }

  private send(message: object): void {
    if (!this.port) throw new Error('editor port unavailable');
    this.port.postMessage(JSON.stringify(message));
  }

  private trySend(message: object): void {
    try { this.send(message); } catch { /* The native side will time out and reconnect. */ }
  }

  private receive(value: unknown): void {
    if (typeof value !== 'string') return;
    let message: Record<string, unknown>;
    try { message = JSON.parse(value) as Record<string, unknown>; } catch { return; }
    if (!message || typeof message !== 'object') return;
    if (message.type === 'init') {
      const init = message as unknown as InitMessage;
      if (typeof init.sessionId !== 'string' || !init.sessionId || !Number.isSafeInteger(init.epoch) ||
        !Number.isSafeInteger(init.revision) || init.revision < 0 || typeof init.source !== 'string' ||
        !['markdown', 'latex', 'svg', 'plain'].includes(init.format) || typeof init.theme !== 'string' ||
        typeof init.language !== 'string' || !['ltr', 'rtl', 'auto'].includes(init.direction) ||
        !Number.isSafeInteger(init.anchor) || !Number.isSafeInteger(init.head) ||
        init.anchor < 0 || init.head < 0 || init.anchor > init.source.length || init.head > init.source.length) return;
      if (this.current?.sessionId === init.sessionId && this.current.epoch === init.epoch) {
        this.send({ type: 'initialized', sessionId: init.sessionId, epoch: init.epoch });
        return;
      }
      if (this.queue && (this.queue.pendingCount() > 0 || this.blocked || this.view.compositionStarted || this.activeFlushes.size > 0)) {
        this.send({ type: 'session-busy', sessionId: init.sessionId, epoch: init.epoch });
        return;
      }
      this.current = init;
      this.blocked = false;
      this.suspended = false;
      this.queue = new EditorChangeQueue(init.sessionId, init.epoch, init.revision, (change) => this.send(change));
      document.documentElement.lang = init.language;
      document.documentElement.dir = init.direction;
      this.view.setState(this.makeState(init));
      this.send({ type: 'initialized', sessionId: init.sessionId, epoch: init.epoch });
      return;
    }
    if (message.type === 'ack') this.queue?.acknowledge(message as unknown as EditorAck);
    if (message.type === 'conflict' && this.current && message.sessionId === this.current.sessionId &&
      message.epoch === this.current.epoch) {
      this.queue?.conflict(message as unknown as EditorConflict);
      this.blocked = true;
      this.view.dispatch({ effects: this.editable.reconfigure(EditorView.editable.of(false)) });
    }
    if (message.type === 'recovery-request' && this.blocked && this.current &&
      message.sessionId === this.current.sessionId && message.epoch === this.current.epoch) {
      const selection = this.view.state.selection.main;
      this.trySend({ type: 'recovery-snapshot', sessionId: this.current.sessionId, epoch: this.current.epoch,
        source: this.view.state.doc.toString(), anchor: selection.anchor, head: selection.head });
    }
    if (message.type === 'recovery-accepted' && this.blocked && this.current &&
      message.sessionId === this.current.sessionId && message.epoch === this.current.epoch &&
      typeof message.nextEpoch === 'number' && Number.isSafeInteger(message.nextEpoch) &&
      message.nextEpoch > this.current.epoch && typeof message.revision === 'number' &&
      Number.isSafeInteger(message.revision) && message.revision >= 0 &&
      typeof message.source === 'string' && message.source === this.view.state.doc.toString()) {
      this.current = { ...this.current, epoch: message.nextEpoch, revision: message.revision };
      this.queue = new EditorChangeQueue(this.current.sessionId, this.current.epoch, message.revision,
        (change) => this.send(change));
      this.blocked = false;
      this.view.dispatch({ effects: this.editable.reconfigure(EditorView.editable.of(true)) });
      this.trySend({ type: 'recovered', sessionId: this.current.sessionId, epoch: this.current.epoch });
      this.publishState();
    }
    if (message.type === 'flush-cancel' && this.current && message.sessionId === this.current.sessionId &&
      message.epoch === this.current.epoch && typeof message.requestId === 'string') {
      this.activeFlushes.get(message.requestId)?.abort();
    }
    if (message.type === 'flush' && this.queue && this.current && message.sessionId === this.current.sessionId &&
      message.epoch === this.current.epoch && typeof message.requestId === 'string') {
      const session = this.current;
      const requestId = message.requestId;
      const queue = this.queue;
      const suspendGeneration = this.suspendGeneration;
      if (this.activeFlushes.has(requestId)) return;
      const controller = new AbortController();
      this.activeFlushes.set(requestId, controller);
      let suspendedByRequest = false;
      controller.signal.addEventListener('abort', () => {
        if (suspendedByRequest && this.suspended && !this.blocked) {
          this.suspended = false;
          this.view.dispatch({ effects: this.editable.reconfigure(EditorView.editable.of(true)) });
        }
      }, { once: true });
      // IME composition can commit another transaction after the save request.
      // Wait for that transaction before establishing the acknowledgement barrier.
      void this.waitForComposition(controller.signal).then(() => {
        if (controller.signal.aborted) throw new Error('editor sync cancelled');
        if (message.suspend === true) {
          if (suspendGeneration !== this.suspendGeneration) throw new Error('suspension cancelled');
          this.suspended = true;
          suspendedByRequest = true;
          this.view.dispatch({ effects: this.editable.reconfigure(EditorView.editable.of(false)) });
        }
        return queue.whenSynced(controller.signal);
      }).then((revision) => {
        if (!controller.signal.aborted && this.current === session) this.trySend({ type: 'flushed', sessionId: session.sessionId, epoch: session.epoch, requestId, revision });
      }).catch(() => {
        if (!controller.signal.aborted && this.current === session) this.trySend({ type: 'flush-failed', sessionId: session.sessionId, epoch: session.epoch, requestId });
      }).finally(() => { this.activeFlushes.delete(requestId); });
    }
    if (message.type === 'command' && this.current && message.sessionId === this.current.sessionId &&
      message.epoch === this.current.epoch && !this.blocked) {
      this.command(message);
    }
    if (message.type === 'configure-theme' && this.current && message.sessionId === this.current.sessionId &&
      message.epoch === this.current.epoch && typeof message.theme === 'string' &&
      ['off', 'github', 'atom', 'vs', 'atom-one', 'visual-studio'].includes(message.theme) &&
      (message.appearance === 'light' || message.appearance === 'dark' || message.appearance === 'system')) {
      this.setTheme?.(message.theme, message.appearance);
    }
    if (message.type === 'configure-locale' && this.current && message.sessionId === this.current.sessionId &&
      message.epoch === this.current.epoch && typeof message.language === 'string' &&
      typeof message.direction === 'string' && ['ltr', 'rtl', 'auto'].includes(message.direction)) {
      document.documentElement.lang = message.language;
      document.documentElement.dir = message.direction;
    }
  }

  private waitForComposition(signal: AbortSignal): Promise<void> {
    if (signal.aborted) return Promise.reject(new Error('editor sync cancelled'));
    if (!this.view.compositionStarted) return Promise.resolve();
    return new Promise((resolve, reject) => {
      let timer: ReturnType<typeof setTimeout> | undefined;
      const cleanup = () => {
        this.view.contentDOM.removeEventListener('compositionend', finish);
        signal.removeEventListener('abort', cancel);
        if (timer !== undefined) clearTimeout(timer);
      };
      const cancel = () => { cleanup(); reject(new Error('editor sync cancelled')); };
      const finish = () => {
        // CodeMirror flushes pending DOM changes before measurement. In particular,
        // some WebViews defer the final composition mutation to the next frame.
        timer = setTimeout(() => this.view.requestMeasure({ read: () => {
          if (!signal.aborted) { cleanup(); resolve(); }
        } }), 0);
      };
      this.view.contentDOM.addEventListener('compositionend', finish, { once: true });
      signal.addEventListener('abort', cancel, { once: true });
    });
  }

  private command(message: Record<string, unknown>): void {
    if (!this.current || typeof message.action !== 'string') return;
    if (message.action === 'resume') {
      this.suspendGeneration++;
      this.suspended = false;
      this.view.dispatch({ effects: this.editable.reconfigure(EditorView.editable.of(true)) });
    } else if (message.action === 'blur') this.view.contentDOM.blur();
    else if (message.action === 'undo') undo(this.view);
    else if (message.action === 'redo') redo(this.view);
    else if (message.action === 'select') {
      const anchor = message.anchor;
      const head = message.head;
      if (typeof anchor !== 'number' || typeof head !== 'number' || !Number.isSafeInteger(anchor) ||
        !Number.isSafeInteger(head) || anchor < 0 || head < 0 ||
        anchor > this.view.state.doc.length || head > this.view.state.doc.length) return;
      this.view.dispatch({ selection: { anchor, head }, effects: EditorView.scrollIntoView(head, { y: 'center' }) });
    } else if (message.action === 'replace') {
      const from = message.from;
      const to = message.to;
      if (typeof from !== 'number' || typeof to !== 'number' || !Number.isSafeInteger(from) ||
        !Number.isSafeInteger(to) || from < 0 || to < from || to > this.view.state.doc.length ||
        typeof message.expected !== 'string' || typeof message.text !== 'string' ||
        this.view.state.sliceDoc(from, to) !== message.expected) return;
      this.view.dispatch({ changes: { from, to, insert: message.text },
        selection: { anchor: from + message.text.length }, annotations: isolateHistory.of('full') });
    } else if (message.action === 'insert') {
      if (typeof message.id !== 'string' || typeof message.before !== 'string' || typeof message.after !== 'string') return;
      const current = this.view.state;
      const edit = insertEditorAction(current.doc, current.selection.main.anchor, current.selection.main.head,
        message.id, message.before, message.after);
      this.view.dispatch({ changes: edit.changes,
        selection: { anchor: edit.caret }, annotations: isolateHistory.of('full') });
      this.view.focus();
    } else return;
    this.publishState();
  }

  private publishState(): void {
    if (!this.current || !this.port) return;
    const selection = this.view.state.selection.main;
    this.trySend({ type: 'editor-state', sessionId: this.current.sessionId, epoch: this.current.epoch,
      anchor: selection.anchor, head: selection.head,
      canUndo: undoDepth(this.view.state) > 0, canRedo: redoDepth(this.view.state) > 0 });
  }

  record(update: ViewUpdate): void {
    if (!this.queue || this.blocked) return;
    if (!update.docChanged) {
      if (update.selectionSet) this.publishState();
      return;
    }
    const changes: EditorChangeRange[] = [];
    update.changes.iterChanges((from, to, _newFrom, _newTo, inserted) => {
      changes.push({ from, to, insert: inserted.toString() });
    });
    this.queue.submit(changes, { anchor: update.state.selection.main.anchor, head: update.state.selection.main.head });
    this.publishState();
  }
}
