import { pageScroll } from './PageScrollPolicy';

/**
 * Preview and outline content scroll with this container. The bounded editor has its own
 * viewport and coordinates scrolling with this container through nested scrolling.
 */
@Component
export struct DocumentScrollLayer {
  @Consume('documentNavigationInsetAbsent') navigationInsetAbsent: boolean;
  scroller: Scroller = new Scroller();
  boundedEditor: boolean = false;
  onViewportChange: (top: number, height: number) => void = (_top: number, _height: number): void => {};
  @State private viewportHeight: number = 0;
  @BuilderParam content: () => void = this.EmptyContent;

  @Builder
  private EmptyContent() {}

  build() {
    Scroll(this.scroller) {
      Column() {
        this.content()
        if (!this.boundedEditor) {
          // 阅读内容延伸到悬浮页签下方，末尾需要留出页签空间。
          Blank().height(56)
          if (this.navigationInsetAbsent) {
            Blank().height($r('sys.float.margin_left'))
          }
        }
      }
      .width('100%')
      .height(this.boundedEditor && this.viewportHeight > 0 ? this.viewportHeight : undefined)
    }
    // faqs-arkui-725: bounded Scroll centers short content unless aligned to the top.
    .align(Alignment.Top)
    .scrollable(ScrollDirection.Vertical)
    .attributeModifier(pageScroll)
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
