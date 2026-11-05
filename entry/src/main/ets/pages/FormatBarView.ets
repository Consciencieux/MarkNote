import { Chip, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { FormatRegistry, InsertAction } from '../document/FormatRegistry';

/** 编辑快捷操作放在导航标题栏的 bottomBuilder 中。 */
@ComponentV2
export struct FormatBarView {
  @Param formatId: string = '';
  @Param onInsert: (action: InsertAction) => void = (_action: InsertAction): void => {};
  // 显式开启系统的触摸流光；未设置时由组件决定是否启用。
  // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-uimaterial
  private material: uiMaterial.Material | undefined = uiMaterial.isImmersiveMaterialSupported() ?
    new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      colorInvert: true,
      // 横向滚动容器会裁切胶囊自带阴影；关闭材质阴影，保留系统材质和光感反馈。
      // https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-common-capability
      applyShadow: false,
      lightEffect: {}
    }) : undefined;

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
