import { LengthMetrics } from '@kit.ArkUI';

/**
 * 帮助、隐私和许可证共用的阅读版心。
 * 12 列栅格按断点居中，基础边距 24vp。内容仍由调用方提供，这里不增加滚动层。
 */
@Component
export struct SettingsReadingFrame {
  @BuilderParam content: () => void = this.empty;

  @Builder
  private empty() {
  }

  build() {
    GridRow({ columns: 12, breakpoints: { reference: BreakpointsReference.ComponentSize } }) {
      GridCol({
        span: { xs: 12, sm: 12, md: 10, lg: 8 },
        offset: { xs: 0, sm: 0, md: 1, lg: 2 }
      }) {
        this.content()
      }
    }
    .width('100%')
    .padding({
      start: LengthMetrics.vp(24),
      end: LengthMetrics.vp(24)
    })
  }
}
