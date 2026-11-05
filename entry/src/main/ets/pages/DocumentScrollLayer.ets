/** HDS immersive-scroll FAQ places the start gap inside a full-height Scroll viewport. */
export const DOCUMENT_SCROLL_START_GAP: number = 56;

/**
 * The single vertical scroll surface for preview, editing, outline, and split panes.
 * Each child is sized to its content so this ArkUI Scroll owns page movement in every tab.
 */
@Component
export struct DocumentScrollLayer {
  scroller: Scroller = new Scroller();
  @BuilderParam content: () => void = this.EmptyContent;

  @Builder
  private EmptyContent() {}

  build() {
    Scroll(this.scroller) {
      this.content()
    }
    .scrollable(ScrollDirection.Vertical)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.On)
    // HDS FAQ faqs-arkui-1095 uses a full-height Scroll with this 56vp content start gap.
    .padding({ top: DOCUMENT_SCROLL_START_GAP })
    .width('100%')
    .height('100%')
  }
}
