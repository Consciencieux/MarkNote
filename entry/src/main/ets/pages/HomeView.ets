import { pageScroll } from './PageScrollPolicy';
import { ComposeListItem, IconType, LengthMetrics, SymbolGlyphModifier } from '@kit.ArkUI';
import { RecentDocument } from '../model/Document';
import { FormatRegistry } from '../document/FormatRegistry';
import { homeMenuWidth, menuMaterialOptions } from './MenuMaterialOptions';
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
  onShare: (item: RecentDocument) => void = (_item: RecentDocument): void => {};
  onCopy: (item: RecentDocument) => void = (_item: RecentDocument): void => {};
  onFavorite: (item: RecentDocument) => void = (_item: RecentDocument): void => {};
  onRemove: (item: RecentDocument) => void = (_item: RecentDocument): void => {};
  onDelete: (item: RecentDocument) => void = (_item: RecentDocument): void => {};
  onMultiSelect: (item: RecentDocument) => void = (_item: RecentDocument): void => {};
  onSelectionChange: (item: RecentDocument, selected: boolean) => void =
    (_item: RecentDocument, _selected: boolean): void => {};
  onEditModeChange: (enabled: boolean) => void = (_enabled: boolean): void => {};

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
  private RecentDocumentContent(item: RecentDocument) {
    ComposeListItem({
      contentItem: {
        iconStyle: IconType.SYSTEM_ICON,
        symbolStyle: new SymbolGlyphModifier($r('sys.symbol.doc_text')),
        primaryText: item.name,
        secondaryText: FormatRegistry.displayTitle(FormatRegistry.byFilename(item.name))
      }
    })
  }

  private selected(uri: string): boolean {
    return this.selectedUris.indexOf(uri) >= 0;
  }

  private recentMenuOptions(): ContextMenuOptions {
    const material = menuMaterialOptions();
    return {
      preview: MenuPreviewMode.IMAGE,
      // 列表行截图保留原尺寸，避免放大后与原行文字错位重叠。
      // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-menu/
      previewAnimationOptions: { scale: [1, 1] },
      hapticFeedbackMode: HapticFeedbackMode.ENABLED,
      backgroundBlurStyle: material.backgroundBlurStyle,
      systemMaterial: material.systemMaterial
    };
  }

  @Builder
  private RecentMenu(item: RecentDocument) {
    Menu() {
      MenuItemGroup() {
        MenuItem({ content: $r('app.string.menu_share'),
          symbolEndIcon: new SymbolGlyphModifier($r('sys.symbol.share')) })
          .onClick(() => this.onShare(item))
        MenuItem({ content: $r('app.string.menu_save_as'),
          symbolEndIcon: new SymbolGlyphModifier($r('sys.symbol.save')) })
          .onClick(() => this.onCopy(item))
      }
      MenuItemGroup() {
        MenuItem({ content: $r('app.string.home_multi_select'),
          symbolEndIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark_circle')) })
          .onClick(() => this.onMultiSelect(item))
        MenuItem({ content: item.favorite === true ? $r('app.string.menu_unfavorite') : $r('app.string.menu_favorite'),
          symbolEndIcon: new SymbolGlyphModifier(item.favorite === true ? $r('sys.symbol.star_fill') : $r('sys.symbol.star')) })
          .onClick(() => this.onFavorite(item))
        MenuItem({ content: $r('app.string.home_remove_record'),
          symbolEndIcon: new SymbolGlyphModifier($r('sys.symbol.minus_circle')) })
          .onClick(() => this.onRemove(item))
      }
      MenuItemGroup() {
        MenuItem({ content: $r('app.string.delete_title'),
          symbolEndIcon: new SymbolGlyphModifier($r('sys.symbol.trash')).fontColor([$r('sys.color.warning')]) })
          .contentFontColor($r('sys.color.warning'))
          .onClick(() => this.onDelete(item))
      }
    }
    .width(homeMenuWidth)
  }

  @Builder
  private RecentRow(item: RecentDocument) {
    if (this.selecting) {
      ListItem() {
        this.RecentDocumentContent(item)
      }
      .selected(this.selected(item.uri))
      // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-listitem/
      .stateStyles({
        normal: { .backgroundColor(Color.Transparent) },
        selected: { .backgroundColor(Color.Transparent) }
      })
      .onSelect((selected: boolean) => this.onSelectionChange(item, selected))
    } else {
      ListItem() {
        this.RecentDocumentContent(item)
      }
      .onClick(() => this.onRecent(item))
      .bindContextMenu(this.RecentMenu(item), ResponseType.LongPress, this.recentMenuOptions())
    }
  }

  build() {
    List({ scroller: this.scroller, spaceWidth: $r('sys.float.padding_level6') }) {
      if (!this.selecting) {
        ListItem() {
          Text(this.favoritesOnly ? $r('app.string.home_favorites') : $r('app.string.home_all'))
            .attributeModifier(pageTitle)
        }
        .selectable(false)

        ListItem() {
          Row() {
            Button($r('app.string.home_new_button'))
              .accessibilityText($r('app.string.home_new'))
              .bindMenu(this.newDocumentMenu(), menuMaterialOptions())
              .layoutWeight(1)
              .margin({ end: LengthMetrics.resource($r('sys.float.padding_level6')) })
            Button($r('app.string.home_open'))
              .accessibilityText($r('app.string.menu_open'))
              .buttonStyle(ButtonStyleMode.NORMAL)
              .layoutWeight(1)
              .onClick(() => this.onOpen())
          }
          .width('100%')
        }
        .selectable(false)
      }

      ForEach(this.recents, (item: RecentDocument) => {
        this.RecentRow(item)
      }, (item: RecentDocument) => JSON.stringify([this.language, item.uri, item.name, item.favorite === true]))
    }
    // https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-layout-development-create-list/
    .enableEditMode(this.selecting)
    .onEditModeChange((enabled: boolean) => this.onEditModeChange(enabled))
    .height('100%')
    .margin({
      start: LengthMetrics.resource($r('sys.float.margin_left')),
      end: LengthMetrics.resource($r('sys.float.margin_right'))
    })
    .attributeModifier(pageScroll)
  }
}
