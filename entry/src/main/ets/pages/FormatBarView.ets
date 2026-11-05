import { SymbolGlyphModifier } from '@kit.ArkUI';
import { FormatRegistry, InsertAction } from '../document/FormatRegistry';

/**
 * 图标按钮的可点热区。出处：Code Linter 规则 @cross-device-app-dev/touch-target-size
 * ——「主要交互元素或控件的可点击热区至少为 48vp×48vp（推荐），不得小于 40vp×40vp」。
 */
const TOUCH_TARGET: number = 48;

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
   * 圆形按钮胶囊（会在编辑区重新多出一块颜色）。因此按兜底处理，但尽量不自己写样式：
   * - 按钮用系统 Button，样式取 ButtonStyleMode.TEXTUAL（枚举说明：纯文本、无背景颜色，
   *   适用于次要操作），按压态由组件给出；
   * - 高度取文档规定的可点热区（见 TOUCH_TARGET），不自己编一个行高；
   * - 图标大小是唯一没有文档依据的值：SymbolGlyph 默认 16fp（API 参考 SymbolGlyph > fontSize）
   *   在按钮里偏小，这里取 24。
   */
  @Builder
  private IconButton(symbol: Resource, label: string, action: () => void) {
    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      SymbolGlyph(symbol)
        .fontSize(24)
        .fontColor([$r('sys.color.icon_primary')])
    }
    .layoutWeight(1)
    .height(TOUCH_TARGET)
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
              .fontSize(24)
              .fontColor([$r('sys.color.icon_primary')])
          }
          .layoutWeight(1)
          .height(TOUCH_TARGET)
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
