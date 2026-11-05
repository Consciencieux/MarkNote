import { SegmentButton, SegmentButtonItemTuple, SegmentButtonOptions, SubHeader } from '@kit.ArkUI';

export const THEME_VALUES: string[] = ['system', 'light', 'dark'];
const THEME_LABELS: string[] = ['跟随系统', '浅色', '深色'];

// 胶囊类单选分段按钮是官方给出的单选切换组件，选中态靠背景板高亮，不使用勾选图标。
const THEME_SEGMENTS: SegmentButtonOptions = SegmentButtonOptions.capsule({
  buttons: [
    { text: THEME_LABELS[0] }, { text: THEME_LABELS[1] }, { text: THEME_LABELS[2] }
  ] as SegmentButtonItemTuple,
  multiply: false
});

/**
 * 设置里的「外观」。选中态用 @Link 与页面共享，页面切主题时这里的高亮跟着走。
 */
@Component
export struct SettingsView {
  @Link selected: number[];
  onChoose: (choice: string) => void = (_choice: string): void => {};

  build() {
    Column() {
      SubHeader({ primaryTitle: '外观' })
      SegmentButton({
        options: THEME_SEGMENTS,
        selectedIndexes: $selected,
        onItemClicked: (index: number) => this.onChoose(THEME_VALUES[index])
      })
        .padding({ left: $r('sys.float.margin_left'), right: $r('sys.float.margin_right') })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
