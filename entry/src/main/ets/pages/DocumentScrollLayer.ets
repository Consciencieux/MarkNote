import { PageScrollPolicy } from './PageScrollPolicy';

/**
 * The single vertical scroll surface for preview, editing, outline, and split panes.
 * Each child is sized to its content so this ArkUI Scroll owns page movement in every tab.
 */
@Component
export struct DocumentScrollLayer {
  private scrollPolicy: PageScrollPolicy<ScrollAttribute> = new PageScrollPolicy<ScrollAttribute>();
  scroller: Scroller = new Scroller();
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
    .width('100%')
    .height('100%')
  }
}
