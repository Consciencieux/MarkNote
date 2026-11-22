import { LengthMetrics } from '@kit.ArkUI';
import { pageContentTop, pageScroll } from './PageScrollPolicy';

export class DocumentWebScroll implements AttributeModifier<WebAttribute> {
  applyNormalAttribute(web: WebAttribute): void {
    web.width('100%').height('100%')
      .verticalScrollBarAccess(true)
      // ArkWeb hands both document edges to the parent Scroll's spring.
      // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-basic-components-web-attributes/#nestedscroll
      .overScrollMode(OverScrollMode.NEVER)
      .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST });
  }
}

export const documentWebScroll = new DocumentWebScroll();

export interface DocumentWebViewport {
  top: number;
  bottom: number;
  caretTop: number;
  caretBottom: number;
  start: number;
  end: number;
}

export const emptyDocumentViewport: DocumentWebViewport = {
  top: 0, bottom: 0, caretTop: 0, caretBottom: 0, start: 0, end: 0
};

export function documentTabClearance(tabBarBottomMargin: number): number {
  // HdsTabs uses its default floating height (56vp). The content shares the bar's bottom margin.
  // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdstabs#barheight
  const bar = LengthMetrics.resource($r('sys.float.tab_bar_default_height')).value;
  return bar + tabBarBottomMargin;
}

/** Shares the bounded, immersive Web viewport between preview and editing. */
@Component
export struct DocumentScrollLayer {
  @Consume('documentTabBarBottomMargin') @Watch('updateViewport') tabBarBottomMargin: number;
  @Consume('documentWorkspaceTop') @Watch('updateViewport') workspaceTop: number;
  @Consume('documentWorkspaceBottom') @Watch('updateViewport') workspaceBottom: number;
  scroller: Scroller = new Scroller();
  onViewportChange: (viewport: DocumentWebViewport) => void = (_viewport: DocumentWebViewport): void => {};
  @State private viewportHeight: number = 0;
  private viewportTop: number = 0;
  private parentOffset: number = 0;
  @BuilderParam content: () => void = this.EmptyContent;

  @Builder
  private EmptyContent() {}

  private updateViewport(): void {
    if (this.viewportHeight <= 0 || this.workspaceBottom <= 0) return;
    const top = Math.max(0, this.workspaceTop - this.viewportTop);
    const bottom = documentTabClearance(this.tabBarBottomMargin) +
      Math.max(0, this.viewportTop + this.viewportHeight - this.workspaceBottom);
    const gap = LengthMetrics.resource(pageContentTop).value;
    this.onViewportChange({
      top, bottom,
      caretTop: Math.max(0, top + this.parentOffset),
      caretBottom: Math.max(0, bottom + gap - this.parentOffset),
      start: LengthMetrics.resource($r('sys.float.margin_left')).value,
      end: LengthMetrics.resource($r('sys.float.margin_right')).value
    });
  }

  build() {
    Column() {
      Scroll(this.scroller) {
        Column() {
          this.content()
        }
        .width('100%')
        .height(this.viewportHeight > 0 ? this.viewportHeight : undefined)
      }
      // faqs-arkui-725: bounded Scroll centers short content unless aligned to the top.
      .align(Alignment.Top)
      .scrollable(ScrollDirection.Vertical)
      .attributeModifier(pageScroll)
      .scrollBar(BarState.Off)
      .onDidScroll(() => {
        this.parentOffset = this.scroller.currentOffset().yOffset;
        this.updateViewport();
      })
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
    })
  }
}
