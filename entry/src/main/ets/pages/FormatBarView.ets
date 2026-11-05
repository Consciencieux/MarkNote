import { SymbolGlyphModifier } from '@kit.ArkUI';
import { FormatRegistry, InsertAction } from '../document/FormatRegistry';

/**
 * The insert bar that sits under the title bar on the edit tab.
 *
 * It is a fixed row, not an accessory view that follows the keyboard: the page keeps its
 * content below the title bar (the same layout the system notes app uses), so the bar never
 * has to be repositioned when the keyboard opens or closes.
 *
 * This is a real @Component rather than a @Builder on purpose. The official @Builder guide
 * says a nested @Builder only refreshes when every level passes its parameters by reference,
 * and faqs-arkui-375 states that a state change drives the UI of a custom component directly
 * but not that of a @Builder. Keeping the bar as a component makes `visible` a plain @Prop
 * that rebuilds this subtree, instead of an attribute on a nested builder that never updates.
 */
@Component
export struct FormatBarView {
  /** Shown only on the tabs that can edit, and only for formats that declare inserts. */
  @Prop visible: boolean = false;
  @Prop formatId: string = '';
  onInsert: (action: InsertAction) => void = (_action: InsertAction): void => {};

  private inserts(): InsertAction[] {
    return FormatRegistry.byId(this.formatId).inserts;
  }

  /** The four most common inserts stay on the bar; the rest move into the more menu. */
  private barInserts(): InsertAction[] {
    return this.inserts().slice(0, 4);
  }

  private moreInserts(): MenuElement[] {
    const rest = this.inserts().slice(4);
    const items: MenuElement[] = [];
    for (let index = 0; index < rest.length; index++) {
      const action = rest[index];
      items.push({
        value: action.label,
        symbolIcon: new SymbolGlyphModifier(action.symbol),
        action: (): void => this.onInsert(action)
      });
    }
    return items;
  }

  /**
   * 插入栏的图标按钮。
   *
   * 这一行在官方组件里没有对应项：HdsNavigation 的菜单只属于标题栏，HdsActionBar 是带背板的
   * 圆形按钮胶囊（会在编辑区重新多出一块颜色）。因此按兜底处理，但尺寸和颜色都不自己填：
   * - 按钮用系统 Button，样式取 ButtonStyleMode.TEXTUAL（枚举说明：纯文本、无背景颜色，
   *   适用于次要操作），按压态由组件给出；
   * - 高度用系统「圆形按钮直径」资源（`sys.float.ohos_id_min_circle_button_diameter`），
   *   不写自己算出来的热区数值；
   * - 图标大小用配套的「圆形按钮图标尺寸」资源（`sys.float.ohos_id_min_circle_button_icon_size`），
   *   不用 SymbolGlyph 默认的 16fp（API 参考 SymbolGlyph > fontSize）。
   * 两个资源名都在 SDK 的系统资源定义里，取值不需要知道。
   */
  @Builder
  private IconButton(symbol: Resource, label: string, action: () => void) {
    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      SymbolGlyph(symbol)
        .fontSize($r('sys.float.ohos_id_min_circle_button_icon_size'))
        .fontColor([$r('sys.color.icon_primary')])
    }
    .layoutWeight(1)
    .height($r('sys.float.ohos_id_min_circle_button_diameter'))
    .accessibilityText(label)
    .onClick(action)
  }

  build() {
    if (this.visible) {
      Row() {
        ForEach(this.barInserts(), (action: InsertAction) => {
          this.IconButton(action.symbol, action.label, (): void => this.onInsert(action))
        }, (action: InsertAction) => action.token)

        if (this.inserts().length > 4) {
          Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            SymbolGlyph($r('sys.symbol.more'))
              .fontSize($r('sys.float.ohos_id_min_circle_button_icon_size'))
              .fontColor([$r('sys.color.icon_primary')])
          }
          .layoutWeight(1)
          .height($r('sys.float.ohos_id_min_circle_button_diameter'))
          .accessibilityText('更多格式')
          .bindMenu(this.moreInserts())
        }
      }
      .width('100%')
      .id('marknote-format-bar')
      // 不铺背板、不画分割线：这一行只是图标按钮，和正文同属页面底色。
    }
  }
}
