import { FrameCallback, LengthMetrics } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { pageContentTop } from './PageScrollPolicy';

export class DocumentWebScroll implements AttributeModifier<WebAttribute> {
  private readonly controller: webview.WebviewController;

  constructor(controller: webview.WebviewController) { this.controller = controller; }

  // The Web nested-scroll example disables gestures from onPageEnd.
  // https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/web-nested-scrolling/
  disableScrollGestures(): void {
    this.controller.setScrollable(false, webview.ScrollType.EVENT);
  }

  applyNormalAttribute(web: WebAttribute): void {
    web.width('100%').height('100%')
      .verticalScrollBarAccess(false)
      .overScrollMode(OverScrollMode.NEVER)
      .onGestureRecognizerJudgeBegin((_event: BaseGestureEvent, recognizer: GestureRecognizer): GestureJudgeResult =>
        recognizer.isBuiltIn() && recognizer.getType() === GestureControl.GestureType.PAN_GESTURE ?
          GestureJudgeResult.REJECT : GestureJudgeResult.CONTINUE);
  }
}

export interface DocumentWebViewport {
  top: number;
  bottom: number;
}

export const emptyDocumentViewport: DocumentWebViewport = { top: 0, bottom: 0 };

export interface DocumentScrollLayout {
  extent: number;
  offset?: number;
  previousOffset?: number;
}

export function documentTabClearance(tabBarBottomMargin: number): number {
  // HdsTabs uses its default floating height (56vp). The content shares the bar's bottom margin.
  // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdstabs#barheight
  const bar = LengthMetrics.resource($r('sys.float.tab_bar_default_height')).value;
  return bar + tabBarBottomMargin;
}

class AfterScrollLayout extends FrameCallback {
  private readonly action: () => void;

  constructor(action: () => void) {
    super();
    this.action = action;
  }

  onIdle(_timeLeftInNano: number): void { this.action(); }
}

/** ArkUI owns the document extent, scrollbar and spring. The Web surface stays viewport-sized. */
@Component
export struct DocumentScrollLayer {
  @Consume('documentTabBarBottomMargin') @Watch('updateViewport') tabBarBottomMargin: number;
  @Consume('documentWorkspaceTop') @Watch('updateViewport') workspaceTop: number;
  @Consume('documentWorkspaceBottom') @Watch('updateViewport') workspaceBottom: number;
  @Prop @Watch('updateScrollLayout') scrollLayout: DocumentScrollLayout = { extent: 0 };
  scroller: Scroller = new Scroller();
  web: webview.WebviewController = new webview.WebviewController();
  onViewportChange: (viewport: DocumentWebViewport) => void = (_viewport: DocumentWebViewport): void => {};
  @State private viewportHeight: number = 0;
  @State private viewport: DocumentWebViewport = emptyDocumentViewport;
  @State private extent: number = 0;
  @State private edgeOffset: number = 0;
  private pageOffset: number = 0;
  private viewportTop: number = 0;
  private pendingOffset: number | undefined;
  private pendingPreviousOffset: number | undefined;
  private scrolling: boolean = false;
  private layoutScheduled: boolean = false;
  private active: boolean = true;
  @BuilderParam content: () => void = this.EmptyContent;

  @Builder
  private EmptyContent() {}

  aboutToDisappear(): void { this.active = false; }

  private updateScrollLayout(): void {
    const extent = this.scrollLayout.extent;
    const offset = this.scrollLayout.offset;
    if (!Number.isFinite(extent) || extent < 0) return;
    this.extent = extent;
    if (typeof offset === 'number' && Number.isFinite(offset)) {
      this.pendingOffset = offset;
      this.pendingPreviousOffset = this.scrollLayout.previousOffset;
    }
    this.scheduleLayout();
  }

  private scheduleLayout(): void {
    if (this.layoutScheduled || this.viewportHeight <= 0) return;
    this.layoutScheduled = true;
    this.getUIContext().postFrameCallback(new AfterScrollLayout((): void => {
      this.layoutScheduled = false;
      if (!this.active || this.viewportHeight <= 0) return;
      if (this.pendingOffset !== undefined) {
        const offset = this.pendingOffset;
        const previous = this.pendingPreviousOffset;
        this.pendingOffset = undefined;
        this.pendingPreviousOffset = undefined;
        // A layout correction must respect input that arrived while ArkWeb was measuring.
        // Web reports a CSS-pixel position, while the native offset can be fractional.
        const current = this.scroller.currentOffset().yOffset;
        if (previous === undefined || (!this.scrolling && Math.abs(current - this.documentOffset(previous)) < 1)) {
          this.scroller.scrollTo({ xOffset: 0, yOffset: this.documentOffset(offset) });
        }
      }
      this.updateWebPosition(true);
    }));
  }

  private documentOffset(offset: number): number {
    return Math.min(this.extent, Math.max(0, offset));
  }

  private updateWebPosition(layoutChanged: boolean = false): void {
    const scrollOffset = this.scroller.currentOffset().yOffset;
    const offset = this.documentOffset(scrollOffset);
    const edgeOffset = offset - scrollOffset;
    if (this.edgeOffset !== edgeOffset) this.edgeOffset = edgeOffset;
    if (!layoutChanged && this.pageOffset === offset) return;
    try {
      if (layoutChanged) {
        this.web.scrollTo(0, offset);
      } else {
        // Dispatch the frame's movement as in Huawei's parent-driven Web scroll example.
        this.web.scrollBy(0, offset - this.pageOffset);
      }
      this.pageOffset = offset;
    } catch { /* Web may not be attached yet. */ }
  }

  private updateViewport(): void {
    if (this.viewportHeight <= 0 || this.workspaceBottom <= 0) return;
    const top = Math.max(0, this.workspaceTop - this.viewportTop);
    const bottom = documentTabClearance(this.tabBarBottomMargin) +
      Math.max(0, this.viewportTop + this.viewportHeight - this.workspaceBottom);
    const gap = LengthMetrics.resource(pageContentTop).value;
    const viewport: DocumentWebViewport = { top: top + gap, bottom };
    if (this.viewport.top === viewport.top && this.viewport.bottom === viewport.bottom) return;
    this.viewport = viewport;
    this.onViewportChange(viewport);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.content()
      }
      .width('100%')
      .height('100%')
      // The Web surface stays fixed in range and follows the native spring beyond the edge.
      .padding({ left: $r('sys.float.margin_left'), right: $r('sys.float.margin_right') })
      .translate({ y: this.edgeOffset })

      Scroll(this.scroller) {
        Column()
          .width('100%')
          .height(this.viewportHeight + this.extent)
      }
      // The scroll layer can handle drags and wheel input while taps reach the Web below.
      // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-hit-test-behavior/
      .hitTestBehavior(HitTestMode.Transparent)
      // faqs-arkui-725: bounded Scroll centers short content unless aligned to the top.
      .align(Alignment.Top)
      .scrollable(ScrollDirection.Vertical)
      .clipContent(ContentClipMode.SAFE_AREA)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Auto)
      .scrollBarMargin({ start: LengthMetrics.vp(this.viewport.top), end: LengthMetrics.vp(this.viewport.bottom) })
      .onScrollStart((): void => { this.scrolling = true; })
      .onScrollStop((): void => { this.scrolling = false; })
      .onDidScroll((): void => this.updateWebPosition())
      .width('100%')
      .height('100%')
    }
    .clip(true)
    .width('100%')
    // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-expand-safe-area
    .height(LayoutPolicy.matchParent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.VERTICAL])
    .onAreaChange((_oldArea: Area, area: Area): void => {
      this.viewportTop = Number(area.globalPosition.y);
      this.viewportHeight = Number(area.height);
      this.updateViewport();
      this.scheduleLayout();
    })
  }
}
