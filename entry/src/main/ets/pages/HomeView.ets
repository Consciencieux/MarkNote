import { ComposeListItem, IconType, SymbolGlyphModifier } from '@kit.ArkUI';
import { RecentDocument } from '../model/Document';
import { FormatRegistry } from '../document/FormatRegistry';

/**
 * 首页文稿列表。新建、打开和最近文稿的动作都交回页面，这里只负责展示和发起。
 */
@Component
export struct HomeView {
  @Prop recents: RecentDocument[] = [];
  scroller: Scroller = new Scroller();
  onNew: (id: string) => void = (_id: string): void => {};
  onOpen: () => void = (): void => {};
  onRecent: (item: RecentDocument) => void = (_item: RecentDocument): void => {};

  /** 新建菜单的条目来自文稿格式注册表，新增格式不用改这里。 */
  private newDocumentMenu(): MenuElement[] {
    const items: MenuElement[] = [];
    const formats = FormatRegistry.all();
    for (let index = 0; index < formats.length; index++) {
      const format = formats[index];
      items.push({
        value: format.sheetTitle,
        action: (): void => this.onNew(format.id)
      });
    }
    return items;
  }

  /**
   * 列表行使用官方 ComposeListItem（ohos-arkui-advanced-composelistitem）：
   * 图标尺寸、主副标题字号和行高都由组件按系统规范给出，
   * 不再手写 Row + SymbolGlyph + 两行 Text 和自行计算的 padding。
   */
  @Builder
  private DocumentRow(title: string, detail: string, symbol: Resource) {
    ComposeListItem({
      contentItem: {
        iconStyle: IconType.SYSTEM_ICON,
        symbolStyle: new SymbolGlyphModifier(symbol),
        primaryText: title,
        secondaryText: detail
      }
    })
  }

  @Builder
  private RecentRow(item: RecentDocument) {
    ListItem() {
      this.DocumentRow(item.name, FormatRegistry.byFilename(item.name).sheetTitle, $r('sys.symbol.doc_text'))
    }
    .onClick(() => this.onRecent(item))
  }

  build() {
    // 首页只承担两件事：开始一篇新文稿/打开已有文件，和回到最近打开过的文稿。
    // 标题「全部」由导航标题栏给出，页面里不再写标语和分组标题。
    // List gap and edge spacing use system resources; clip(false) follows
    // 《设置动态模糊样式》(ui-design-navigation-dynamic-blur) so rows can scroll under the title bar.
    List({ scroller: this.scroller, spaceWidth: $r('sys.float.padding_level6') }) {
      ListItem() {
        Row() {
          Button('新建文稿')
            .bindMenu(this.newDocumentMenu())
            .layoutWeight(1)
            .margin({ right: $r('sys.float.padding_level6') })
          Button('打开文件')
            // Button API (ts-basic-components-button)：打开文件采用普通操作的 NORMAL 样式。
            .buttonStyle(ButtonStyleMode.NORMAL)
            .layoutWeight(1)
            .onClick(() => this.onOpen())
        }
        .width('100%')
      }

      ForEach(this.recents, (item: RecentDocument) => {
        this.RecentRow(item)
      }, (item: RecentDocument) => item.uri)
    }
    // Keep the list at the available width and use system margin resources for its edges.
    .layoutWeight(1)
    .margin({ left: $r('sys.float.margin_left'), right: $r('sys.float.margin_right') })
    .clip(false)
  }
}
