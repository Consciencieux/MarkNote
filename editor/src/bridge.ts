import type { EditorAck, EditorChangeMessage, EditorChangeRange, EditorConflict, EditorSelection } from '../../shared/editor-protocol.ts';

type Waiter = { sequence: number; resolve: (revision: number) => void; reject: (error: Error) => void };

/** Keeps incremental edits until the native document confirms their sequence. */
export class EditorChangeQueue {
  private sessionId: string;
  private epoch: number;
  private initialRevision: number;
  private nextSequence: number = 1;
  private acknowledged: number = 0;
  private pending: EditorChangeMessage[] = [];
  private waiters: Waiter[] = [];
  private blocked: boolean = false;
  private deliveryPaused: boolean = false;
  private send: (message: EditorChangeMessage) => void;

  constructor(sessionId: string, epoch: number, revision: number, send: (message: EditorChangeMessage) => void) {
    this.sessionId = sessionId;
    this.epoch = epoch;
    this.initialRevision = revision;
    this.send = send;
  }

  submit(changes: EditorChangeRange[], selection: EditorSelection, endingChange?: EditorChangeRange): EditorChangeMessage {
    if (this.blocked) throw new Error('editor sync conflict');
    const sequence = this.nextSequence++;
    const message: EditorChangeMessage = {
      type: 'change', sessionId: this.sessionId, epoch: this.epoch,
      sequence, baseRevision: this.initialRevision + sequence - 1,
      changes: changes.map((item) => ({ from: item.from, to: item.to, insert: item.insert })),
      selection: { anchor: selection.anchor, head: selection.head }
    };
    if (endingChange) message.endingChange = endingChange;
    this.pending.push(message);
    if (this.deliveryPaused) {
      this.retransmit();
    } else {
      try { this.send(message); } catch { this.deliveryPaused = true; }
    }
    return message;
  }

  acknowledge(message: EditorAck): boolean {
    if (this.blocked || !message || message.type !== 'ack' || message.sessionId !== this.sessionId ||
      message.epoch !== this.epoch || !Number.isSafeInteger(message.sequence) ||
      message.sequence <= this.acknowledged || message.sequence >= this.nextSequence ||
      message.revision !== this.initialRevision + message.sequence) return false;
    this.acknowledged = message.sequence;
    this.pending = this.pending.filter((item) => item.sequence > message.sequence);
    const ready = this.waiters.filter((waiter) => waiter.sequence <= message.sequence);
    this.waiters = this.waiters.filter((waiter) => waiter.sequence > message.sequence);
    for (const waiter of ready) waiter.resolve(this.initialRevision + waiter.sequence);
    return true;
  }

  conflict(message: EditorConflict): void {
    if (!message || message.type !== 'conflict' || message.sessionId !== this.sessionId || message.epoch !== this.epoch) return;
    this.blocked = true;
    const waiters = this.waiters;
    this.waiters = [];
    for (const waiter of waiters) waiter.reject(new Error('editor sync conflict'));
  }

  retransmit(): void {
    if (this.blocked) return;
    for (const message of this.pending) {
      try { this.send(message); } catch { this.deliveryPaused = true; return; }
    }
    this.deliveryPaused = false;
  }

  pendingCount(): number { return this.pending.length; }

  whenSynced(signal?: AbortSignal): Promise<number> {
    if (this.blocked) return Promise.reject(new Error('editor sync conflict'));
    if (signal?.aborted) return Promise.reject(new Error('editor sync cancelled'));
    const sequence = this.nextSequence - 1;
    if (sequence <= this.acknowledged) return Promise.resolve(this.initialRevision + sequence);
    return new Promise((resolve, reject) => {
      const cleanup = () => signal?.removeEventListener('abort', cancel);
      const waiter: Waiter = { sequence,
        resolve: (revision) => { cleanup(); resolve(revision); },
        reject: (error) => { cleanup(); reject(error); } };
      const cancel = () => {
        this.waiters = this.waiters.filter((item) => item !== waiter);
        waiter.reject(new Error('editor sync cancelled'));
      };
      this.waiters.push(waiter);
      signal?.addEventListener('abort', cancel, { once: true });
    });
  }
}
