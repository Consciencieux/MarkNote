import { PageScrollPolicy } from './PageScrollPolicy';

/**
 * The single vertical scroll surface for preview, editing, outline, and split panes.
 * Each child is sized to its content so this ArkUI Scroll owns page movement in every tab.
 */
@Component
export struct DocumentScrollLayer {
  private scrollPolicy: PageScrollPolicy<ScrollAttribute> = new PageScrollPolicy<ScrollAttribute>();
  scroller: Scroller = new Scroller();
  onViewportChange: (top: number, height: number) => void = (_top: number, _height: number): void => {};
  @State private viewportHeight: number = 0;
  @BuilderParam content: () => void = this.EmptyContent;

  @Builder
  private EmptyContent() {}

  build() {
    Scroll(this.scroller) {
      this.content()
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
