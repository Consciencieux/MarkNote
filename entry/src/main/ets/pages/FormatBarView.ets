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
   * 插入栏的图标按钮。图标尺寸和行高都是兜底值：
   * 文档没有为「自定义插入栏」给出图标尺寸，SymbolGlyph 默认 16fp 偏小，
   * 因此图标取 24vp、行高取 56vp（与 MINI 标题栏同高）。
   * 颜色用系统图标色，不额外铺底：按钮本身只是整行里的可点区域。
   */
  @Builder
  private IconButton(symbol: Resource, label: string, action: () => void) {
    Column() {
      SymbolGlyph(symbol)
        .fontSize(24)
        .fontColor([$r('sys.color.icon_primary')])
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
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
          Column() {
            SymbolGlyph($r('sys.symbol.more'))
              .fontSize(24)
              .fontColor([$r('sys.color.icon_primary')])
          }
          .layoutWeight(1)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .accessibilityText('更多格式')
          .bindMenu(this.moreInserts())
        }
      }
      .width('100%')
      .height(56)
      .id('marknote-format-bar')
      // 不铺背板、不画分割线：这一行只是图标按钮，和正文同属页面底色。
      // 之前手写的 sub_background 底板和 1vp 下边框都是自造的分隔样式。
    }
  }
}
