/** Copy sent with one preview update. Fields match the strings ArkWeb already understands. */
export interface PreviewCopy {
  lang: string;
  rtl: boolean;
  empty: string;
  failed: string;
  unsafe: string;
  markdownFailed: string;
  svgUnsafe: string;
  svgInvalid: string;
  svgRejected: string;
  mathFailed: string;
  tikzFailed: string;
  imageName: string;
  imageSlot: string;
}

/** One preview request. Identity is the session id plus the text revision, not the route counter. */
export interface PreviewCommand {
  kind: string;
  source: string;
  theme: string;
  codeTheme: string;
  revision: number;
  documentId: number;
  mode: string;
  text: PreviewCopy;
}

/**
 * Per-preview send queue: at most one request in flight and one latest waiting request.
 * pause keeps the latest request without sending it. dispose drops everything.
 */
export class PreviewDispatch {
  private sendRequest: (request: PreviewCommand) => Promise<void>;
  private latest: PreviewCommand | null = null;
  private paused: boolean = false;
  private disposed: boolean = false;
  private sending: boolean = false;

  constructor(sendRequest: (request: PreviewCommand) => Promise<void>) {
    this.sendRequest = sendRequest;
  }

  request(value: PreviewCommand): void {
    if (this.disposed) return;
    this.latest = value;
    if (!this.paused) this.pump();
  }

  pause(): void {
    this.paused = true;
  }

  resume(): void {
    if (this.disposed) return;
    this.paused = false;
    this.pump();
  }

  dispose(): void {
    this.disposed = true;
    this.paused = true;
    this.latest = null;
  }

  private pump(): void {
    if (this.sending || this.paused || this.disposed || this.latest === null) return;
    const value = this.latest;
    this.latest = null;
    this.sending = true;
    this.sendRequest(value).then((): void => {
      this.sending = false;
      this.pump();
    }).catch((): void => {
      this.sending = false;
      this.pump();
    });
  }
}
