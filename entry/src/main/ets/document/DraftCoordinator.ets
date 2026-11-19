import { common } from '@kit.AbilityKit';
import { DraftSnapshot } from '../model/Document';
import { LocalState } from '../storage/LocalState';

const IDLE_MS: number = 450;
const DEADLINE_MS: number = 2000;
const MAX_AUTO_ATTEMPTS: number = 4;

function retryDelay(attempt: number): number {
  if (attempt <= 1) return 500;
  if (attempt === 2) return 1000;
  if (attempt === 3) return 2000;
  return 4000;
}

class DraftTask {
  kind: string = 'write';
  snapshot: DraftSnapshot = new DraftSnapshot();
  op: number = 0;
  sessionId: number = 0;
  forced: boolean = false;
  done: Promise<boolean> = Promise.resolve(false);
  resolve: (value: boolean) => void = (_value: boolean): void => {};
  reject: (error: Error) => void = (_error: Error): void => {};

  constructor(kind: string, snapshot: DraftSnapshot, op: number, forced: boolean) {
    this.kind = kind;
    this.snapshot = snapshot;
    this.op = op;
    this.sessionId = snapshot.sessionId;
    this.forced = forced;
    this.done = new Promise<boolean>((resolve: (value: boolean) => void, reject: (error: Error) => void): void => {
      this.resolve = resolve;
      this.reject = reject;
    });
  }
}

/**
 * One writer for the private recovery file.
 * Automatic saves keep one in-flight write and one latest snapshot.
 * A failed automatic snapshot is retried with a short backoff, then reported.
 * A later edit, a clear, or a session change retires that snapshot for good.
 * A checkpoint waits until its own snapshot is durable.
 */
export class DraftCoordinator {
  onError: (sessionId: number, error: Error) => void = (_sessionId: number, _error: Error): void => {};
  private context: common.UIAbilityContext;
  private activeSession: number = 0;
  private nextOp: number = 1;
  private pendingAuto: DraftTask | null = null;
  private queue: DraftTask[] = [];
  private running: boolean = false;
  private inflight: Promise<boolean> | null = null;
  private idleTimer: number = -1;
  private deadlineTimer: number = -1;
  private retryTimer: number = -1;
  private retryAttempt: number = 0;
  private retrySnapshot: DraftSnapshot | null = null;
  /** Automatic writes created before this operation must not be retried. */
  private minLiveOp: number = 0;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  activate(sessionId: number): void {
    this.activeSession = sessionId;
    this.disarm();
    this.cancelRetry();
    this.supersede(this.nextOp);
    this.pendingAuto = null;
    const kept: DraftTask[] = [];
    for (let index = 0; index < this.queue.length; index++) {
      const task = this.queue[index];
      if (task.sessionId === sessionId) {
        kept.push(task);
      } else if (task.forced && task.kind === 'write') {
        task.reject(new Error('stale session'));
      } else {
        task.resolve(false);
      }
    }
    this.queue = kept;
  }

  schedule(snapshot: DraftSnapshot): void {
    if (snapshot.sessionId !== this.activeSession) return;
    this.cancelRetry();
    this.pendingAuto = new DraftTask('write', snapshot, this.nextOp++, false);
    this.supersede(this.pendingAuto.op);
    this.armIdle();
    this.armDeadline();
  }

  checkpoint(snapshot: DraftSnapshot): Promise<void> {
    if (snapshot.sessionId !== this.activeSession) return Promise.reject(new Error('stale session'));
    const task = new DraftTask('write', snapshot, this.nextOp++, true);
    this.enqueue(task);
    return task.done.then((): void => {});
  }

  clear(snapshot: DraftSnapshot): Promise<boolean> {
    this.cancelRetry();
    const task = new DraftTask('clear', snapshot, this.nextOp++, true);
    this.supersede(task.op);
    if (this.pendingAuto !== null && this.pendingAuto.op < task.op) {
      this.pendingAuto = null;
      this.disarm();
    }
    this.enqueue(task);
    return task.done;
  }

  flush(): Promise<void> {
    if (this.retrySnapshot !== null && this.pendingAuto === null &&
      this.retrySnapshot.sessionId === this.activeSession) {
      const shot = this.retrySnapshot;
      this.cancelRetry();
      this.enqueue(new DraftTask('write', shot, this.nextOp++, false));
    } else {
      this.cancelRetry();
    }
    this.commitAuto();
    const pending: Promise<boolean>[] = [];
    if (this.inflight !== null) pending.push(this.inflight);
    for (let index = 0; index < this.queue.length; index++) pending.push(this.queue[index].done);
    this.pump();
    return Promise.all(pending).then((): void => {});
  }

  private armIdle(): void {
    if (this.idleTimer >= 0) clearTimeout(this.idleTimer);
    this.idleTimer = setTimeout((): void => this.commitAuto(), IDLE_MS);
  }

  private armDeadline(): void {
    if (this.deadlineTimer >= 0) return;
    this.deadlineTimer = setTimeout((): void => this.commitAuto(), DEADLINE_MS);
  }

  private disarm(): void {
    if (this.idleTimer >= 0) clearTimeout(this.idleTimer);
    if (this.deadlineTimer >= 0) clearTimeout(this.deadlineTimer);
    this.idleTimer = -1;
    this.deadlineTimer = -1;
  }

  private commitAuto(): void {
    this.disarm();
    const task = this.pendingAuto;
    this.pendingAuto = null;
    if (task === null || task.sessionId !== this.activeSession) return;
    this.enqueue(task);
  }

  private enqueue(task: DraftTask): void {
    if (task.kind === 'write') {
      const kept: DraftTask[] = [];
      for (let index = 0; index < this.queue.length; index++) {
        const queued = this.queue[index];
        const olderAuto = !task.forced && queued.kind === 'write' && !queued.forced &&
          queued.sessionId === task.sessionId;
        const otherSession = queued.kind === 'write' && queued.sessionId !== task.sessionId;
        if (olderAuto) {
          queued.resolve(false);
        } else if (otherSession) {
          if (queued.forced) queued.reject(new Error('stale session'));
          else queued.resolve(false);
        } else {
          kept.push(queued);
        }
      }
      this.queue = kept;
    }
    this.queue.push(task);
    this.pump();
  }

  private pump(): void {
    if (this.running) return;
    this.running = true;
    void this.drain();
  }

  private async drain(): Promise<void> {
    while (this.queue.length > 0) {
      const task = this.queue.shift() as DraftTask;
      await this.run(task);
    }
    this.running = false;
    if (this.queue.length > 0) this.pump();
  }

  private async run(task: DraftTask): Promise<void> {
    this.inflight = task.done;
    try {
      if (task.kind === 'clear') {
        const newerPending = this.pendingAuto !== null && this.pendingAuto.op > task.op;
        let newerQueued = false;
        for (let index = 0; index < this.queue.length; index++) {
          const queued = this.queue[index];
          if (queued.kind === 'write' && queued.op > task.op) newerQueued = true;
        }
        if (newerPending || newerQueued || task.sessionId !== this.activeSession) {
          task.resolve(false);
          return;
        }
        await LocalState.clearDraft(this.context);
        task.resolve(true);
        return;
      }
      if (task.sessionId !== this.activeSession) {
        if (task.forced) task.reject(new Error('stale session'));
        else task.resolve(false);
        return;
      }
      await LocalState.writeDraft(this.context, task.snapshot.data);
      if (!task.forced) this.cancelRetry();
      task.resolve(true);
    } catch (error) {
      const message = error instanceof Error ? error.message :
        (typeof error === 'object' && error !== null && typeof (error as Error).message === 'string' ?
          (error as Error).message : 'draft failed');
      const wrapped = new Error(message.length > 0 ? message : 'draft failed');
      if (task.forced) task.reject(wrapped);
      else this.failAuto(task, wrapped);
    } finally {
      this.inflight = null;
    }
  }

  private failAuto(task: DraftTask, error: Error): void {
    const newerPending = this.pendingAuto !== null;
    let newerQueued = false;
    for (let index = 0; index < this.queue.length; index++) {
      const queued = this.queue[index];
      if (queued.kind === 'write' && queued.sessionId === task.sessionId) newerQueued = true;
    }
    if (task.sessionId !== this.activeSession || task.op < this.minLiveOp || newerPending || newerQueued) {
      task.resolve(false);
      return;
    }
    this.retryAttempt++;
    if (this.retryAttempt >= MAX_AUTO_ATTEMPTS) {
      this.retryAttempt = 0;
      this.retrySnapshot = null;
      task.resolve(false);
      this.onError(task.sessionId, error);
      return;
    }
    this.retrySnapshot = task.snapshot;
    const delay = retryDelay(this.retryAttempt);
    const op = task.op;
    task.resolve(false);
    this.armRetry(delay, op);
  }

  private supersede(op: number): void {
    if (op > this.minLiveOp) this.minLiveOp = op;
  }

  private armRetry(delay: number, op: number): void {
    if (this.retryTimer >= 0) clearTimeout(this.retryTimer);
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      const shot = this.retrySnapshot;
      this.retrySnapshot = null;
      if (shot === null || op < this.minLiveOp || shot.sessionId !== this.activeSession ||
        this.pendingAuto !== null) return;
      this.enqueue(new DraftTask('write', shot, this.nextOp++, false));
    }, delay);
  }

  private cancelRetry(): void {
    if (this.retryTimer >= 0) clearTimeout(this.retryTimer);
    this.retryTimer = -1;
    this.retrySnapshot = null;
    this.retryAttempt = 0;
  }
}
