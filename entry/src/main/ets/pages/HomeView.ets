import { pageScroll } from './PageScrollPolicy';
import { ComposeListItem, IconType, LengthMetrics, SymbolGlyphModifier } from '@kit.ArkUI';
import { RecentDocument } from '../model/Document';
import { FormatRegistry } from '../document/FormatRegistry';
import { menuMaterialOptions } from './MenuMaterialOptions';
import { pageTitle } from './TextRoles';

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
  scroller: Scroller = new Scroller();
  onNew: (id: string) => void = (_id: string): void => {};
  onOpen: () => void = (): void => {};
  onRecent: (item: RecentDocument) => void = (_item: RecentDocument): void => {};
  @Prop selecting: boolean = false;
  @Prop selectedUris: string[] = [];
  @Prop selectionAllFavorite: boolean = false;
  onShare: (item: RecentDocument) => void = (_item: RecentDocument): void => {};
  onCopy: (item: RecentDocument) => void = (_item: RecentDocument): void => {};
  onFavorite: (item: RecentDocument) => void = (_item: RecentDocument): void => {};
  onRemove: (item: RecentDocument) => void = (_item: RecentDocument): void => {};
  onDelete: (item: RecentDocument) => void = (_item: RecentDocument): void => {};
  onMultiSelect: (item: RecentDocument) => void = (_item: RecentDocument): void => {};
  onToggleSelected: (item: RecentDocument) => void = (_item: RecentDocument): void => {};
  onShareSelected: () => void = (): void => {};
  onFavoriteSelected: () => void = (): void => {};
  onRemoveSelected: () => void = (): void => {};
  onDeleteSelected: () => void = (): void => {};

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

  private selected(uri: string): boolean {
    return this.selectedUris.indexOf(uri) >= 0;
  }

  /**
   * 前三项进入官方网格，后三项保持纵向菜单。
   * gridStyle 只作用于标准 MenuItem，预览使用被长按的列表行。
   * https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-menu
   */
  private recentMenuOptions(): ContextMenuOptions {
    const material = menuMaterialOptions();
    const options: ContextMenuOptions = {
      preview: MenuPreviewMode.IMAGE,
      gridStyle: {
        count: 3,
        horizontalSize: 3,
        position: MenuGridPosition.TOP
      }
    };
    options.backgroundBlurStyle = material.backgroundBlurStyle;
    options.systemMaterial = material.systemMaterial;
    return options;
  }

  private menuItem(label: ResourceStr, symbol: Resource): MenuItemOptions {
    const options: MenuItemOptions = {
      content: label,
      symbolStartIcon: new SymbolGlyphModifier(symbol)
    };
    return options;
  }

  @Builder
  private RecentMenu(item: RecentDocument) {
    Menu() {
      MenuItem(this.menuItem($r('app.string.menu_share'), $r('sys.symbol.share')))
        .onClick(() => this.onShare(item))
      MenuItem(this.menuItem($r('app.string.home_save_copy'), $r('sys.symbol.square_and_arrow_down')))
        .onClick(() => this.onCopy(item))
      MenuItem(this.menuItem($r('app.string.home_multi_select'), $r('sys.symbol.checkmark_square')))
        .onClick(() => this.onMultiSelect(item))
      MenuItem(this.menuItem(item.favorite === true ? $r('app.string.home_unfavorite') : $r('app.string.menu_favorite'),
        item.favorite === true ? $r('sys.symbol.star_fill') : $r('sys.symbol.star')))
        .onClick(() => this.onFavorite(item))
      MenuItem(this.menuItem($r('app.string.home_remove_record'), $r('sys.symbol.minus_circle')))
        .onClick(() => this.onRemove(item))
      MenuItem(this.menuItem($r('app.string.delete_title'), $r('sys.symbol.trash')))
        .contentFontColor($r('sys.color.warning'))
        .onClick(() => this.onDelete(item))
    }
  }

  @Builder
  private SelectionAction(symbol: Resource, label: Resource, warning: boolean, action: () => void) {
    Button() {
      Column() {
        SymbolGlyph(symbol)
          .fontSize($r('sys.float.Subtitle_M'))
          .fontColor([warning ? $r('sys.color.warning') : $r('sys.color.icon_primary')])
        Text(label)
          .fontSize($r('sys.float.Caption_L'))
          .fontColor(warning ? $r('sys.color.warning') : $r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
    }
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .layoutWeight(1)
    .enabled(this.selectedUris.length > 0)
    .onClick(action)
  }

  @Builder
  private RecentRow(item: RecentDocument) {
    ListItem() {
      Row() {
        if (this.selecting) {
          Checkbox({ name: item.uri, group: 'marknote-recent' })
            .select(this.selected(item.uri))
            .margin({ end: LengthMetrics.resource($r('sys.float.padding_level4')) })
            .onChange((checked: boolean) => {
              if (checked !== this.selected(item.uri)) this.onToggleSelected(item);
            })
        }
        Column() {
          this.DocumentRow(item.name, FormatRegistry.displayTitle(FormatRegistry.byFilename(item.name)),
            $r('sys.symbol.doc_text'))
        }
        .layoutWeight(1)
      }
      .width('100%')
    }
    .onClick(() => {
      if (this.selecting) this.onToggleSelected(item);
      else this.onRecent(item);
    })
    .bindContextMenu(this.RecentMenu(item), ResponseType.LongPress, this.recentMenuOptions())
  }

  build() {
    // 首页只承担两件事：开始一篇新文稿/打开已有文件，和回到最近打开过的文稿。
    // 标题位于内容区，避免占用标题栏中分段按钮的空间。
    // List keeps its native row layout; the shared policy owns safe areas and scrolling behavior.
    Column() {
    List({ scroller: this.scroller, spaceWidth: $r('sys.float.padding_level6') }) {
      ListItem() {
        Text(this.favoritesOnly ? $r('app.string.home_favorites') : $r('app.string.home_all'))
          .attributeModifier(pageTitle)
      }

      ListItem() {
        Row() {
          Button($r('app.string.home_new'))
            .bindMenu(this.newDocumentMenu(), menuMaterialOptions())
            .layoutWeight(1)
            .margin({ end: LengthMetrics.resource($r('sys.float.padding_level6')) })
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
      }, (item: RecentDocument) => JSON.stringify([
        this.language, item.uri, item.name, item.favorite === true, this.selecting
      ]))
    }
    // Keep the list at the available width and use system margin resources for its edges.
    .layoutWeight(1)
    .margin({
      start: LengthMetrics.resource($r('sys.float.margin_left')),
      end: LengthMetrics.resource($r('sys.float.margin_right'))
    })
    .attributeModifier(pageScroll)
    if (this.selecting) {
      Row() {
        this.SelectionAction($r('sys.symbol.share'), $r('app.string.menu_share'), false,
          (): void => this.onShareSelected())
        this.SelectionAction(this.selectionAllFavorite ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'),
          this.selectionAllFavorite ? $r('app.string.home_unfavorite') : $r('app.string.menu_favorite'), false,
          (): void => this.onFavoriteSelected())
        this.SelectionAction($r('sys.symbol.minus_circle'), $r('app.string.home_remove_record'), false,
          (): void => this.onRemoveSelected())
        this.SelectionAction($r('sys.symbol.trash'), $r('app.string.menu_delete'), true,
          (): void => this.onDeleteSelected())
      }
      .id('marknote-home-share')
      .width('100%')
      .padding({
        top: $r('sys.float.padding_level2'),
        bottom: $r('sys.float.padding_level4')
      })
    }
    }
    .width('100%')
    .height('100%')
  }
}
