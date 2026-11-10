import { PageScrollPolicy } from './PageScrollPolicy';
import { ComposeListItem, IconType, SymbolGlyphModifier } from '@kit.ArkUI';
import { RecentDocument } from '../model/Document';
import { FormatRegistry } from '../document/FormatRegistry';
import { menuMaterialOptions } from './MenuMaterialOptions';

/**
 * 首页文稿列表。新建、打开和最近文稿的动作都交回页面，这里只负责展示和发起。
 */
@Component
export struct HomeView {
  /**
   * 格式名称是取好的字符串。首页被包在 @Builder 里，按值传入的 language 不会更新，
   * 所以这里直接订阅 AppStorage，并用它作为列表键。
   * https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-builder
   */
  @StorageLink('marknote_language') language: string = 'default';
  @Prop favoritesOnly: boolean = false;
  @Prop recents: RecentDocument[] = [];
  private scrollPolicy: PageScrollPolicy<ListAttribute> = new PageScrollPolicy<ListAttribute>();
  scroller: Scroller = new Scroller();
  onNew: (id: string) => void = (_id: string): void => {};
  onOpen: () => void = (): void => {};
  onRecent: (item: RecentDocument) => void = (_item: RecentDocument): void => {};
  onRemoveRecent: (item: RecentDocument) => void = (_item: RecentDocument): void => {};

  /** 新建菜单的条目来自文稿格式注册表，新增格式不用改这里。 */
  private newDocumentMenu(): MenuElement[] {
    const items: MenuElement[] = [];
    // build 会调用这里。列表为空时 ForEach 读不到 language，新建菜单仍要跟着语言重建。
    if (this.language.length === 0) return items;
    const formats = FormatRegistry.all();
    for (let index = 0; index < formats.length; index++) {
      const format = formats[index];
      items.push({
        value: FormatRegistry.displayTitle(format),
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
  private RecentMenu(item: RecentDocument) {
    Menu() {
      MenuItem({
        content: this.favoritesOnly ? $r('app.string.home_unfavorite') : $r('app.string.home_remove_record')
      })
        .onClick(() => this.onRemoveRecent(item))
    }
  }

  @Builder
  private RecentRow(item: RecentDocument) {
    ListItem() {
      this.DocumentRow(item.name, FormatRegistry.displayTitle(FormatRegistry.byFilename(item.name)),
        $r('sys.symbol.doc_text'))
    }
    .onClick(() => this.onRecent(item))
    .bindContextMenu(this.RecentMenu(item), ResponseType.LongPress, menuMaterialOptions())
  }

  build() {
    // 首页只承担两件事：开始一篇新文稿/打开已有文件，和回到最近打开过的文稿。
    // 标题位于内容区，避免占用标题栏中分段按钮的空间。
    // List keeps its native row layout; the shared policy owns safe areas and scrolling behavior.
    List({ scroller: this.scroller, spaceWidth: $r('sys.float.padding_level6') }) {
      ListItem() {
        Text(this.favoritesOnly ? $r('app.string.home_favorites') : $r('app.string.home_all'))
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
      }

      ListItem() {
        Row() {
          Button($r('app.string.home_new'))
            .bindMenu(this.newDocumentMenu(), menuMaterialOptions())
            .layoutWeight(1)
            .margin({ right: $r('sys.float.padding_level6') })
          Button($r('app.string.home_open'))
            // Button API (ts-basic-components-button)：打开文件采用普通操作的 NORMAL 样式。
            .buttonStyle(ButtonStyleMode.NORMAL)
            .layoutWeight(1)
            .onClick(() => this.onOpen())
        }
        .width('100%')
      }

      ForEach(this.recents, (item: RecentDocument) => {
        this.RecentRow(item)
      }, (item: RecentDocument) => `${this.language}:${item.uri}`)
    }
    // Keep the list at the available width and use system margin resources for its edges.
    .layoutWeight(1)
    .margin({ left: $r('sys.float.margin_left'), right: $r('sys.float.margin_right') })
    .attributeModifier(this.scrollPolicy)
  }
}
