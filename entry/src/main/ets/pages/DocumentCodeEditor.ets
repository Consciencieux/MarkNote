import { webview } from '@kit.ArkWeb';
import { EditorBridge } from '../document/EditorBridge';
import type { EditorSelection } from '../../../../../shared/editor-protocol';

export interface CodeEditorCommand {
  action: string;
  anchor?: number;
  head?: number;
  from?: number;
  to?: number;
  expected?: string;
  text?: string;
  id?: string;
  before?: string;
  after?: string;
}

interface EditorPortMessage {
  type: string;
  sessionId?: string;
  epoch?: number;
  revision?: number;
  requestId?: string;
  anchor?: number;
  head?: number;
  canUndo?: boolean;
  canRedo?: boolean;
  source?: string;
}

/** Page-owned handle. Saving or leaving must wait for flush to succeed. */
export class DocumentCodeEditorController {
  private flushAction: ((suspend: boolean) => Promise<boolean>) | null = null;
  private commandAction: ((command: CodeEditorCommand) => boolean) | null = null;

  bind(action: (suspend: boolean) => Promise<boolean>, command: (command: CodeEditorCommand) => boolean): void {
    this.flushAction = action;
    this.commandAction = command;
  }
  unbind(): void { this.flushAction = null; this.commandAction = null; }
  flush(suspend: boolean = false): Promise<boolean> {
    return this.flushAction ? this.flushAction(suspend) : Promise.resolve(false);
  }
  command(command: CodeEditorCommand): boolean {
    if (!this.commandAction) return false;
    return this.commandAction(command);
  }
}

/** Standalone editor host; callers retain ownership of the document and its files. */
@Component
export struct DocumentCodeEditor {
  @Prop sessionId: string = '';
  @Prop epoch: number = 1;
  @Prop source: string = '';
  @Prop formatId: string = 'markdown';
  @Prop @Watch('updateTheme') theme: string = 'github';
  @Prop @Watch('updateTheme') appearance: string = 'system';
  @Prop webTheme: string = 'system';
  @Prop @Watch('updateLocale') language: string = 'zh-CN';
  @Prop @Watch('updateLocale') textDirection: string = 'ltr';
  controller: DocumentCodeEditorController = new DocumentCodeEditorController();
  onChange: (expected: string, source: string, anchor: number, head: number) => boolean =
    (_expected: string, _source: string, _anchor: number, _head: number): boolean => false;
  onConflict: () => void = (): void => {};
  onFind: () => void = (): void => {};
  onRecover: (expected: string, source: string, anchor: number, head: number) => boolean =
    (_expected: string, _source: string, _anchor: number, _head: number): boolean => false;
  onState: (anchor: number, head: number, canUndo: boolean, canRedo: boolean) => void =
    (_anchor: number, _head: number, _canUndo: boolean, _canRedo: boolean): void => {};
  private web: webview.WebviewController = new webview.WebviewController();
  private ports: webview.WebMessagePort[] = [];
  private sourceBuffer: string = '';
  private activeEpoch: number = 1;
  private bridge: EditorBridge | null = null;
  private ready: boolean = false;
  private recovering: boolean = false;
  private requestNumber: number = 0;
  private waiting: Map<string, (value: boolean) => void> = new Map();

  aboutToAppear(): void {
    this.sourceBuffer = this.source;
    this.activeEpoch = this.epoch;
    this.resetBridge();
    this.controller.bind((suspend: boolean): Promise<boolean> => this.flush(suspend), (command: CodeEditorCommand): boolean => {
      if (!this.ready) return false;
      try {
        this.send(JSON.stringify({ type: 'command', sessionId: this.sessionId, epoch: this.activeEpoch,
          action: command.action, anchor: command.anchor, head: command.head, from: command.from, to: command.to,
          expected: command.expected, text: command.text, id: command.id, before: command.before, after: command.after }));
        return true;
      } catch { return false; }
    });
  }

  private resetBridge(): void {
    this.bridge = new EditorBridge(this.sessionId, this.activeEpoch, 0,
      (): string => this.sourceBuffer,
      (source: string, selection: EditorSelection): void => {
        if (!this.onChange(this.sourceBuffer, source, selection.anchor, selection.head)) {
          throw new Error('document update rejected');
        }
        this.sourceBuffer = source;
      });
  }

  aboutToDisappear(): void {
    this.ready = false;
    this.controller.unbind();
    this.waiting.forEach((resolve: (value: boolean) => void): void => resolve(false));
    this.waiting.clear();
    if (this.ports.length > 1) {
      try { this.ports[1].close(); } catch { /* Page already released. */ }
    }
    this.ports = [];
  }

  private send(message: string): void {
    if (this.ports.length <= 1) throw new Error('editor port unavailable');
    this.ports[1].postMessageEvent(message);
  }

  private updateTheme(): void {
    if (!this.ready) return;
    this.send(JSON.stringify({ type: 'configure-theme', sessionId: this.sessionId, epoch: this.activeEpoch,
      theme: this.theme, appearance: this.appearance }));
  }

  private updateLocale(): void {
    if (!this.ready) return;
    this.send(JSON.stringify({ type: 'configure-locale', sessionId: this.sessionId, epoch: this.activeEpoch,
      language: this.language, direction: this.textDirection }));
  }

  private connect(): void {
    const previous = this.ports;
    try {
      this.ports = this.web.createWebMessagePorts();
      const port = this.ports[1];
      port.onMessageEvent((message: webview.WebMessage): void => {
        if (this.ports.length <= 1 || this.ports[1] !== port) return;
        if (typeof message === 'string') this.receive(message);
      });
      this.web.postMessage('__marknote_editor_port__', [this.ports[0]], '*');
      if (previous.length > 1) {
        try { previous[1].close(); } catch { /* Port was already released. */ }
      }
    } catch {
      this.ports = previous;
      this.onConflict();
    }
  }

  private receive(raw: string): void {
    let message: EditorPortMessage;
    try { message = JSON.parse(raw) as EditorPortMessage; } catch { return; }
    if (!message || typeof message.type !== 'string') return;
    if (message.type === 'ready') {
      const format = this.formatId === 'tex-math' ? 'latex' : this.formatId;
      this.send(JSON.stringify({ type: 'init', sessionId: this.sessionId, epoch: this.activeEpoch,
        revision: 0, source: this.sourceBuffer, format: format, theme: this.theme, appearance: this.appearance,
        language: this.language, direction: this.textDirection, anchor: 0, head: 0 }));
      return;
    }
    if (message.sessionId !== this.sessionId || message.epoch !== this.activeEpoch) return;
    if (message.type === 'find-request') { this.onFind(); return; }
    if (message.type === 'initialized') { this.ready = true; return; }
    if (message.type === 'recovered') { this.recovering = false; return; }
    if (message.type === 'editor-state') {
      if (typeof message.anchor !== 'number' || typeof message.head !== 'number' ||
        !Number.isInteger(message.anchor) || !Number.isInteger(message.head) ||
        message.anchor < 0 || message.head < 0 || message.anchor > this.sourceBuffer.length ||
        message.head > this.sourceBuffer.length || typeof message.canUndo !== 'boolean' ||
        typeof message.canRedo !== 'boolean') return;
      this.onState(message.anchor, message.head, message.canUndo, message.canRedo);
      return;
    }
    if (message.type === 'change' && this.bridge !== null) {
      const result = this.bridge.receive(message);
      if (result.type === 'conflict') {
        this.send(JSON.stringify(result));
        if (!this.recovering) {
          this.recovering = true;
          this.send(JSON.stringify({ type: 'recovery-request', sessionId: this.sessionId, epoch: this.activeEpoch }));
        }
        return;
      }
      this.send(JSON.stringify(result));
      return;
    }
    if (message.type === 'recovery-snapshot' && this.recovering && typeof message.source === 'string' &&
      typeof message.anchor === 'number' && typeof message.head === 'number' &&
      Number.isSafeInteger(message.anchor) && Number.isSafeInteger(message.head) &&
      message.anchor >= 0 && message.head >= 0 && message.anchor <= message.source.length &&
      message.head <= message.source.length) {
      const recoveredSource = message.source;
      if (!this.onRecover(this.sourceBuffer, recoveredSource, message.anchor, message.head)) {
        this.onConflict();
        return;
      }
      const oldEpoch = this.activeEpoch;
      this.sourceBuffer = recoveredSource;
      this.activeEpoch++;
      this.resetBridge();
      this.send(JSON.stringify({ type: 'recovery-accepted', sessionId: this.sessionId, epoch: oldEpoch,
        nextEpoch: this.activeEpoch, revision: 0, source: recoveredSource }));
      return;
    }
    if ((message.type === 'flushed' || message.type === 'flush-failed') && message.requestId) {
      const resolve = this.waiting.get(message.requestId);
      this.waiting.delete(message.requestId);
      if (resolve) {
        const valid = message.type === 'flushed' && this.bridge !== null && typeof message.revision === 'number' &&
          Number.isSafeInteger(message.revision) && message.revision >= 0 && message.revision <= this.bridge.revision();
        if (!valid) this.onConflict();
        resolve(valid);
      }
    }
  }

  private flush(suspend: boolean): Promise<boolean> {
    if (!this.ready) {
      this.connect();
      this.onConflict();
      return Promise.resolve(false);
    }
    const requestId = `${++this.requestNumber}`;
    return new Promise<boolean>((resolve: (value: boolean) => void): void => {
      const timer = setTimeout((): void => {
        this.waiting.delete(requestId);
        try {
          this.send(JSON.stringify({ type: 'flush-cancel', sessionId: this.sessionId, epoch: this.activeEpoch,
            requestId: requestId }));
        } catch { /* Reconnection also cancels requests on the old port. */ }
        this.ready = false;
        this.connect();
        this.onConflict();
        resolve(false);
      }, 5000);
      this.waiting.set(requestId, (value: boolean): void => { clearTimeout(timer); resolve(value); });
      try {
        this.send(JSON.stringify({ type: 'flush', sessionId: this.sessionId, epoch: this.activeEpoch,
          requestId: requestId, suspend: suspend }));
      } catch {
        const pending = this.waiting.get(requestId);
        this.waiting.delete(requestId);
        if (pending) pending(false);
        this.ready = false;
        this.connect();
        this.onConflict();
      }
    });
  }

  build() {
    Web({ src: $rawfile('editor/index.html'), controller: this.web })
      .javaScriptAccess(true)
      .domStorageAccess(false)
      .darkMode(this.webTheme === 'system' ? WebDarkMode.Auto :
        (this.webTheme === 'dark' ? WebDarkMode.On : WebDarkMode.Off))
      .backgroundColor($r('sys.color.ohos_id_color_background'))
      .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
      .onPageEnd(() => this.connect())
      .width('100%').height('100%')
  }
}
