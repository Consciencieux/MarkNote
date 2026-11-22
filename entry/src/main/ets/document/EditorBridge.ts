import type { EditorBridgeResult, EditorChangeMessage, EditorChangeRange, EditorSelection } from '../../../../../shared/editor-protocol.ts';

/** Orders editor deltas before the current document service accepts them. */
export class EditorBridge {
  private sessionId: string;
  private epoch: number;
  private currentRevision: number;
  private nextSequence: number = 1;
  private conflicted: boolean = false;
  private read: () => string;
  private write: (source: string, selection: EditorSelection, endingChange?: EditorChangeRange) => void;

  constructor(sessionId: string, epoch: number, revision: number, read: () => string,
    write: (source: string, selection: EditorSelection, endingChange?: EditorChangeRange) => void) {
    this.sessionId = sessionId;
    this.epoch = epoch;
    this.currentRevision = revision;
    this.read = read;
    this.write = write;
  }

  revision(): number { return this.currentRevision; }

  private conflict(reason: string): EditorBridgeResult {
    this.conflicted = true;
    return { type: 'conflict', sessionId: this.sessionId, epoch: this.epoch,
      sequence: this.nextSequence - 1, revision: this.currentRevision, reason };
  }

  receive(value: unknown): EditorBridgeResult {
    if (typeof value !== 'object' || value === null) return this.conflict('invalid-message');
    const message = value as EditorChangeMessage;
    if (message.sessionId !== this.sessionId || message.epoch !== this.epoch) return { type: 'stale' };
    if (this.conflicted) return this.conflict('resync-required');
    if (message.type !== 'change' || !Number.isSafeInteger(message.sequence) || message.sequence < 1) {
      return this.conflict('invalid-message');
    }
    if (message.sequence < this.nextSequence) {
      return { type: 'ack', sessionId: this.sessionId, epoch: this.epoch,
        sequence: this.nextSequence - 1, revision: this.currentRevision };
    }
    if (message.sequence !== this.nextSequence || message.baseRevision !== this.currentRevision) {
      return this.conflict('revision-mismatch');
    }
    if (!Array.isArray(message.changes) || !message.selection ||
      !Number.isSafeInteger(message.selection.anchor) || !Number.isSafeInteger(message.selection.head)) {
      return this.conflict('invalid-message');
    }
    try {
      const source = this.read();
      let end = 0;
      let resultLength = source.length;
      for (const range of message.changes) {
        if (!EditorBridge.validRange(range, end, source.length)) return this.conflict('invalid-range');
        resultLength += range.insert.length - (range.to - range.from);
        end = range.to;
      }
      if (message.selection.anchor < 0 || message.selection.head < 0 ||
        message.selection.anchor > resultLength || message.selection.head > resultLength) {
        return this.conflict('invalid-selection');
      }
      let updated = source;
      for (let index = message.changes.length - 1; index >= 0; index--) {
        const range = message.changes[index];
        updated = updated.slice(0, range.from) + range.insert + updated.slice(range.to);
      }
      this.write(updated, message.selection, message.endingChange);
      this.currentRevision++;
      this.nextSequence++;
      return { type: 'ack', sessionId: this.sessionId, epoch: this.epoch,
        sequence: this.nextSequence - 1, revision: this.currentRevision };
    } catch {
      return this.conflict('document-update-failed');
    }
  }

  private static validRange(range: EditorChangeRange, previousEnd: number, sourceLength: number): boolean {
    return !!range && Number.isSafeInteger(range.from) && Number.isSafeInteger(range.to) &&
      typeof range.insert === 'string' && range.from >= previousEnd && range.to >= range.from && range.to <= sourceLength;
  }
}
