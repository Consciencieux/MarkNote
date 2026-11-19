export interface EditorChangeRange { from: number; to: number; insert: string }
export interface EditorSelection { anchor: number; head: number }
export interface EditorChangeMessage {
  type: 'change';
  sessionId: string;
  epoch: number;
  sequence: number;
  baseRevision: number;
  changes: EditorChangeRange[];
  selection: EditorSelection;
}
export interface EditorAck {
  type: 'ack';
  sessionId: string;
  epoch: number;
  sequence: number;
  revision: number;
}
export interface EditorConflict {
  type: 'conflict';
  sessionId: string;
  epoch: number;
  sequence: number;
  revision: number;
  reason: string;
}
export interface EditorStale { type: 'stale' }
export type EditorBridgeResult = EditorAck | EditorConflict | EditorStale;
