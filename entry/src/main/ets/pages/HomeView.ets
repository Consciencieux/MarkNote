import { ComposeListItem, IconType, SubHeader, SymbolGlyphModifier } from '@kit.ArkUI';
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

  @Builder
  private RecentHeader() {
    SubHeader({ primaryTitle: '最近文稿' })
  }

  /**
   * 列表行使用官方 ComposeListItem：图标尺寸、主副标题字号和行高都由组件按系统规范给出，
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
    // 卡片分组之间没有默认间隔：ListItemGroup 的 space 只作用于组内 ListItem，
    // 组与组的间隔由 List({ space }) 给出。12vp 与卡片自身的左右外边距一致。
    List({ scroller: this.scroller, space: 12 }) {
      ListItem() {
        Column({ space: 12 }) {
          Text('离线编辑，随时保存到自己的文件。')
            .fontSize($r('sys.float.ohos_id_text_size_body1'))
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
          Row({ space: 12 }) {
            Button('新建文稿')
              .bindMenu(this.newDocumentMenu())
              .layoutWeight(1)
            Button('打开文件')
              .buttonStyle(ButtonStyleMode.NORMAL)
              .layoutWeight(1)
              .onClick(() => this.onOpen())
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      }

      ListItemGroup({ header: this.RecentHeader, style: ListItemGroupStyle.CARD }) {
        if (this.recents.length === 0) {
          ListItem() {
            Text('最近打开的文件会显示在这里')
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          }
        } else {
          ForEach(this.recents, (item: RecentDocument) => {
            this.RecentRow(item)
          }, (item: RecentDocument) => item.uri)
        }
      }
    }
    .width('100%')
    .height('100%')
    .edgeEffect(EdgeEffect.Spring)
  }
}
