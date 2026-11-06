import { Chip, SymbolGlyphModifier } from '@kit.ArkUI';
import { FormatRegistry, InsertAction } from '../document/FormatRegistry';
import { formatChipMaterial } from './ImmersiveMaterials';

/** 编辑快捷操作放在导航标题栏的 bottomBuilder 中。 */
@ComponentV2
export struct FormatBarView {
  @Param formatId: string = '';
  @Param onInsert: (action: InsertAction) => void = (_action: InsertAction): void => {};
  private material = formatChipMaterial();

  build() {
    Scroll() {
      // 使用 ChipGroup 文档给出的默认项间距和左右边距。
      // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ohos-arkui-advanced-chipgroup
      Row({ space: 8 }) {
        ForEach(FormatRegistry.byId(this.formatId).inserts, (action: InsertAction) => {
          // Chip 的点击态用于执行操作；字号、图标比例、圆角和按压反馈均使用组件默认值。
          // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ohos-arkui-advanced-chip
          Chip({
            label: { text: action.label },
            prefixSymbol: { normal: new SymbolGlyphModifier(action.symbol) },
            allowClose: false,
            backgroundColor: this.material ? Color.Transparent : undefined,
            backgroundSystemMaterial: this.material,
            onClicked: (): void => this.onInsert(action)
          })
        }, (action: InsertAction) => action.label)
      }
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .id('marknote-format-bar')
  }
}
