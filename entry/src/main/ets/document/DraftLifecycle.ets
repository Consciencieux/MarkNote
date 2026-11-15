import { RecoveryData } from '../model/Document';

/**
 * 草稿定时器、写盘和清盘分开。
 * 回调只认当前绑定的会话和修订；销毁后的旧回调不能再写。
 */
export class DraftLifecycle {
  timer: number = -1;
  disposed: boolean = false;
  sessionId: string = '';
  revision: number = -1;

  bind(sessionId: string, revision: number): void {
    this.sessionId = sessionId;
    this.revision = revision;
  }

  /** 只取消定时器，不写草稿。 */
  cancel(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  dispose(): void {
    this.disposed = true;
    this.cancel();
  }

  accepts(sessionId: string, revision: number): boolean {
    return !this.disposed && sessionId === this.sessionId && revision === this.revision;
  }

  schedule(delay: number, commit: (sessionId: string, revision: number) => void): void {
    this.cancel();
    if (this.disposed) return;
    const sessionId = this.sessionId;
    const revision = this.revision;
    this.timer = setTimeout(() => {
      this.timer = -1;
      if (!this.accepts(sessionId, revision)) return;
      commit(sessionId, revision);
    }, delay);
  }
}

/** 保存结果只能清掉仍属于该会话的草稿。 */
export function mayClearDraft(savedSessionId: string, currentSessionId: string, draftSessionId: string): boolean {
  if (savedSessionId.length === 0 || savedSessionId !== currentSessionId) return false;
  if (draftSessionId.length > 0 && draftSessionId !== currentSessionId) return false;
  return true;
}

/** 同一会话里，较旧的修订不能覆盖已经落盘的较新修订。 */
export function mayWriteDraft(sessionId: string, revision: number, persistedSessionId: string,
  persistedRevision: number): boolean {
  if (persistedSessionId.length > 0 && persistedSessionId === sessionId && persistedRevision > revision) {
    return false;
  }
  return true;
}

/**
 * 旧草稿没有会话字段时补上默认值，不因缺字段丢弃正文。
 * 正文是否与已保存文本相同，由读取方决定。
 */
export function normalizeDraft(parsed: RecoveryData): RecoveryData | null {
  if (typeof parsed.text !== 'string' || typeof parsed.savedText !== 'string' ||
    typeof parsed.name !== 'string' || typeof parsed.uri !== 'string') {
    return null;
  }
  if (typeof parsed.sessionId !== 'string') parsed.sessionId = '';
  if (typeof parsed.revision !== 'number' || parsed.revision < 0) parsed.revision = 0;
  parsed.formatVersion = 1;
  return parsed;
}
