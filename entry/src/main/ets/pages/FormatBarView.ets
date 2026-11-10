import { Chip, SymbolGlyphModifier } from '@kit.ArkUI';
import { FormatRegistry, InsertAction } from '../document/FormatRegistry';
import { AppText } from '../i18n/AppText';
import { formatChipMaterial } from './ImmersiveMaterials';

/**
 * 编辑快捷操作放在导航标题栏的 bottomBuilder 中。
 * 标题栏用 @Builder 创建本组件，按值传入的 language 不会更新，所以语言直接订阅 AppStorage。
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-builder
 */
@Component
export struct FormatBarView {
  @Prop formatId: string = '';
  /** 放进列表键里，语言切换后重新取快捷操作的文字。 */
  @StorageLink('marknote_language') language: string = 'default';
  onInsert: (action: InsertAction) => void = (_action: InsertAction): void => {};
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
            label: { text: AppText.text(action.label) },
            prefixSymbol: { normal: new SymbolGlyphModifier(action.symbol) },
            allowClose: false,
            backgroundColor: this.material ? Color.Transparent : undefined,
            backgroundSystemMaterial: this.material,
            onClicked: (): void => this.onInsert(action)
          })
        }, (action: InsertAction) => `${this.language}:${action.id}`)
      }
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .id('marknote-format-bar')
  }
}
