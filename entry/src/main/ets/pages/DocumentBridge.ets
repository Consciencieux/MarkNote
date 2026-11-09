/**
 * 首页和文稿页之间的两个询问。
 *
 * 文稿状态在 DocumentView 里，首页只负责导航，所以「这篇能离开吗」和「请先处理未保存
 * 的改动再离开」都得由首页通过这个桥问过去。文稿页在 aboutToAppear 里接上，
 * 在 aboutToDisappear 里复位成安全默认值（允许离开），避免首页对着已经销毁的实例调用。
 */
export class DocumentBridge {
  /** 处理未保存的改动，true 表示可以继续。 */
  saveBeforeLeaving: () => Promise<boolean> = (): Promise<boolean> => Promise.resolve(true);
  /** 保存后关闭会话并请首页弹栈。 */
  requestLeave: () => void = (): void => {};
  /** 文稿页 aboutToAppear 完成载入后为 true。首页据此等待真正的离开确认。 */
  private attached: boolean = false;
  private pendingReady: (() => void) | null = null;

  markAttached(): void {
    this.attached = true;
    const ready = this.pendingReady;
    this.pendingReady = null;
    if (ready !== null) ready();
  }

  markDetached(): void {
    this.attached = false;
  }

  /** 打开队列同一时刻只等待一次，所以只需记住一个回调。 */
  whenAttached(): Promise<void> {
    if (this.attached) return Promise.resolve();
    return new Promise<void>((resolve: () => void): void => {
      this.pendingReady = resolve;
    });
  }
}

export const documentBridge: DocumentBridge = new DocumentBridge();
