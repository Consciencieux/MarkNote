import { LengthMetrics } from '@kit.ArkUI';
import { pageScroll, PageScrollPolicy } from './PageScrollPolicy';

export function documentTabClearance(tabBarBottomMargin: number): number {
  const bar = LengthMetrics.resource($r('sys.float.tab_bar_default_height')).value;
  return bar + tabBarBottomMargin;
}

/**
 * Preview and outline content scroll with this container. The bounded editor has its own
 * viewport and coordinates scrolling with this container through nested scrolling.
 */
@Component
export struct DocumentScrollLayer {
  @Consume('documentTabBarBottomMargin') tabBarBottomMargin: number;
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
      }
      .padding(this.boundedEditor ? 0 : {
        start: LengthMetrics.resource($r('sys.float.margin_left')),
        end: LengthMetrics.resource($r('sys.float.margin_right'))
      })
      .width('100%')
      .height(this.boundedEditor && this.viewportHeight > 0 ? this.viewportHeight : undefined)
    }
    // faqs-arkui-725: bounded Scroll centers short content unless aligned to the top.
    .align(Alignment.Top)
    .scrollable(ScrollDirection.Vertical)
    .attributeModifier(this.boundedEditor ? pageScroll :
      new PageScrollPolicy(false, documentTabClearance(this.tabBarBottomMargin)))
    // The bounded Web scrolls the source. This outer Scroll only coordinates its native safe area.
    .scrollBar(this.boundedEditor ? BarState.Off : BarState.Auto)
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
