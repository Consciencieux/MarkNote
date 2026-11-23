import { FrameCallback, LengthMetrics } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { pageContentTop } from './PageScrollPolicy';

export class DocumentWebScroll implements AttributeModifier<WebAttribute> {
  private readonly controller: webview.WebviewController;

  constructor(controller: webview.WebviewController) { this.controller = controller; }

  applyNormalAttribute(web: WebAttribute): void {
    web.width('100%').height('100%')
      .verticalScrollBarAccess(false)
      .overScrollMode(OverScrollMode.NEVER)
      // Huawei's Web nested-scroll guide, "滚动偏移量由滚动父组件统一派发".
      .onControllerAttached((): void => this.controller.setScrollable(false, webview.ScrollType.EVENT))
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
  @State private pageOffset: number = 0;
  private viewportTop: number = 0;
  private pendingOffset: number | undefined;
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
    if (typeof offset === 'number' && Number.isFinite(offset)) this.pendingOffset = offset;
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
        this.pendingOffset = undefined;
        this.scroller.scrollTo({ xOffset: 0, yOffset: this.documentOffset(offset) });
      }
      this.updateWebPosition(true);
    }));
  }

  private documentOffset(offset: number): number {
    return Math.min(this.extent, Math.max(0, offset));
  }

  private updateWebPosition(layoutChanged: boolean = false): void {
    const offset = this.documentOffset(this.scroller.currentOffset().yOffset);
    if (!layoutChanged && this.pageOffset === offset) return;
    this.pageOffset = offset;
    try { this.web.scrollTo(0, offset); } catch { /* Web may not be attached yet. */ }
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
    Column() {
      Scroll(this.scroller) {
        Stack({ alignContent: Alignment.TopStart }) {
          Column() {
            this.content()
          }
          .width('100%')
          .height(this.viewportHeight > 0 ? this.viewportHeight : undefined)
          // Give the native scrollbar a gutter outside the Web surface's mouse selection area.
          .padding({ left: $r('sys.float.margin_left'), right: $r('sys.float.margin_right') })
          // Cancel in-range movement of the surface. At either edge, only the native spring moves it.
          .translate({ y: this.pageOffset })
        }
        .width('100%')
        .height(this.viewportHeight > 0 ? this.viewportHeight + this.extent : undefined)
      }
      // faqs-arkui-725: bounded Scroll centers short content unless aligned to the top.
      .align(Alignment.Top)
      .scrollable(ScrollDirection.Vertical)
      .clipContent(ContentClipMode.SAFE_AREA)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Auto)
      .scrollBarMargin({ start: LengthMetrics.vp(this.viewport.top), end: LengthMetrics.vp(this.viewport.bottom) })
      .onDidScroll((): void => this.updateWebPosition())
      .width('100%')
      .height('100%')
    }
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
