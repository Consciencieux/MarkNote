/**
 * 首页和文稿页之间的离开确认以及页面显示状态。
 *
 * aboutToAppear 只保证完成载入；HdsNavDestination.onShown 才表示页面完成显示。
 * 外部打开请求在文稿可见后才询问未保存的修改，避免弹窗出现在导航转场中。
 */
export class DocumentBridge {
  /** 处理未保存的改动，true 表示可以继续。 */
  saveBeforeLeaving: () => Promise<boolean> = (): Promise<boolean> => Promise.resolve(true);
  /** 保存后关闭会话并请首页弹栈。 */
  requestLeave: () => void = (): void => {};
  private attached: boolean = false;
  private visible: boolean = false;
  private pendingReady: ((ready: boolean) => void) | null = null;
  private readyTimer: number = -1;

  markAttached(): void {
    this.attached = true;
    this.resolveIfVisible();
  }

  markShown(): void {
    this.visible = true;
    this.resolveIfVisible();
  }

  markHidden(): void {
    this.visible = false;
  }

  markDetached(): void {
    this.attached = false;
    this.visible = false;
    this.cancelWait();
  }

  private resolveIfVisible(): void {
    if (this.attached && this.visible) this.finishWait(true);
  }

  private finishWait(ready: boolean): void {
    if (this.readyTimer >= 0) {
      clearTimeout(this.readyTimer);
      this.readyTimer = -1;
    }
    const resolve = this.pendingReady;
    this.pendingReady = null;
    if (resolve !== null) resolve(ready);
  }

  /** 页面销毁或首页退出时中断等待，不让打开队列永久挂起。 */
  cancelWait(): void {
    this.finishWait(false);
  }

  /** 同一时刻仅有一个外部打开请求等待，超时或销毁则拒绝本次切换。 */
  whenVisible(timeoutMs: number = 15000): Promise<boolean> {
    if (this.attached && this.visible) return Promise.resolve(true);
    if (this.pendingReady !== null) return Promise.resolve(false);
    return new Promise<boolean>((resolve: (ready: boolean) => void): void => {
      this.pendingReady = resolve;
      this.readyTimer = setTimeout((): void => this.finishWait(false), timeoutMs);
    });
  }
}

export const documentBridge: DocumentBridge = new DocumentBridge();
