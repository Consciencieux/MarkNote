import { PageScrollPolicy } from './PageScrollPolicy';

/**
 * The single vertical scroll surface for preview, editing, outline, and split panes.
 * Each child is sized to its content so this ArkUI Scroll owns page movement in every tab.
 */
@Component
export struct DocumentScrollLayer {
  private scrollPolicy: PageScrollPolicy<ScrollAttribute> = new PageScrollPolicy<ScrollAttribute>();
  @Consume('documentNavigationInsetAbsent') navigationInsetAbsent: boolean;
  scroller: Scroller = new Scroller();
  onViewportChange: (top: number, height: number) => void = (_top: number, _height: number): void => {};
  @State private viewportHeight: number = 0;
  @BuilderParam content: () => void = this.EmptyContent;

  @Builder
  private EmptyContent() {}

  build() {
    Scroll(this.scroller) {
      Column() {
        this.content()
        // HdsTabs 悬浮样式默认高度为 56vp；内容末尾留出同等空间，避免被悬浮页签遮挡。
        // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdstabs
        Blank().height(56)
        if (this.navigationInsetAbsent) {
          Blank().height($r('sys.float.margin_left'))
        }
      }.width('100%')
    }
    // faqs-arkui-725: bounded Scroll centers short content unless aligned to the top.
    .align(Alignment.Top)
    .scrollable(ScrollDirection.Vertical)
    .attributeModifier(this.scrollPolicy)
    .onDidScroll(() => {
      this.onViewportChange(this.scroller.currentOffset().yOffset, this.viewportHeight);
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.viewportHeight = Number(newArea.height);
      this.onViewportChange(this.scroller.currentOffset().yOffset, this.viewportHeight);
    })
    .width('100%')
    .height('100%')
  }
}
