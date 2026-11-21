import { SymbolGlyphModifier, UIContext } from '@kit.ArkUI';
import { AppText } from '../i18n/AppText';

export async function chooseDocumentEncoding(context: UIContext): Promise<string> {
  try {
    const result = await context.getPromptAction().showActionMenu({
      title: AppText.text($r('app.string.menu_reopen_encoding')),
      buttons: [
        { text: 'UTF-8', color: $r('sys.color.font_primary') },
        { text: 'UTF-16 LE', color: $r('sys.color.font_primary') },
        { text: 'UTF-16 BE', color: $r('sys.color.font_primary') },
        { text: 'GB18030', color: $r('sys.color.font_primary') }
      ]
    });
    return ['utf-8', 'utf-16le', 'utf-16be', 'gb18030'][result.index] ?? '';
  } catch { return ''; }
}


/**
 * 菜单内容通过全局 @Builder 交给 ComponentContent 渲染，拿不到页面实例，所以用这个桥把
 * 点击转回页面：页面在 aboutToAppear 里接上自己的处理，菜单只负责发起动作。
 */
export class MenuBridge {
  openFile: () => void = (): void => {};
  saveAs: () => void = (): void => {};
  reopenEncoding: () => void = (): void => {};
  share: () => void = (): void => {};
  deleteDocument: () => void = (): void => {};
  save: () => void = (): void => {};
  showDocumentActions: boolean = false;
  canReopen: boolean = false;
  canDeleteDocument: boolean = false;
  favorite: boolean = false;
  toggleFavorite: () => void = (): void => {};
  openSettings: () => void = (): void => {};
  sortOrder: string = 'modified';
  setSortOrder: (order: string) => void = (_order: string): void => {};
  find: () => void = (): void => {};
  closeDocument: () => void = (): void => {};
  showCloseDocument: boolean = false;
  /** 打开文稿页标题栏的菜单；锚点 id 由文稿页的标题栏提供。 */
  openDocumentMenu: () => void = (): void => {};
  /** 先收起已打开的菜单再执行动作，首页提供实现。 */
  dismiss: (next: () => void) => void = (next: () => void): void => next();
}

export const menuBridge: MenuBridge = new MenuBridge();

/**
 * 首页标题栏的四宫格菜单。首页内容区已经有「新建文稿」和「打开文件」两个按钮，
 * 菜单里提供文稿排序和设置。
 */
@Component
struct SortMenuView {
  private option(label: Resource, order: string): MenuItemOptions {
    const options: MenuItemOptions = { content: label };
    if (menuBridge.sortOrder === order) {
      options.symbolEndIcon = new SymbolGlyphModifier($r('sys.symbol.checkmark'));
    }
    return options;
  }

  build() {
    Menu() {
      MenuItem(this.option($r('app.string.sort_modified'), 'modified'))
        .selected(menuBridge.sortOrder === 'modified')
        .onClick(() => menuBridge.setSortOrder('modified'))
      MenuItem(this.option($r('app.string.sort_opened'), 'opened'))
        .selected(menuBridge.sortOrder === 'opened')
        .onClick(() => menuBridge.setSortOrder('opened'))
      MenuItem(this.option($r('app.string.sort_name'), 'name'))
        .selected(menuBridge.sortOrder === 'name')
        .onClick(() => menuBridge.setSortOrder('name'))
      MenuItem(this.option($r('app.string.sort_type'), 'type'))
        .selected(menuBridge.sortOrder === 'type')
        .onClick(() => menuBridge.setSortOrder('type'))
    }
  }
}

@Component
struct HomeMenuView {
  @Builder
  private SortMenu() {
    SortMenuView()
  }

  build() {
    Menu() {
      MenuItemGroup() {
        MenuItem({ content: $r('app.string.sort_menu'), builder: (): void => { this.SortMenu(); } })
      }
      MenuItemGroup() {
        MenuItem({ content: $r('app.string.settings') })
          .onClick(() => menuBridge.openSettings())
      }
    }
    // HarmonyOS 菜单设计指南规定泛手机菜单宽度为 224vp。
    // https://developer.huawei.com/consumer/cn/doc/design-guides/menu-0000001957001877/
    .width(224)
    .subMenuExpandingMode(SubMenuExpandingMode.EMBEDDED_EXPAND)
  }
}

@Builder
export function HomeMenuContent() {
  HomeMenuView()
}

/**
 * 使用 MenuItemGroup 按操作类型分组；具体项目和排序由应用功能决定。
 */
@Builder
export function DocumentMenuContent() {
  Menu() {
    MenuItemGroup() {
      MenuItem({ content: $r('app.string.menu_open') })
        .onClick(() => menuBridge.openFile())
      MenuItem({ content: $r('app.string.menu_save_as') })
        .onClick(() => menuBridge.saveAs())
      if (menuBridge.canReopen) {
        MenuItem({ content: $r('app.string.menu_reopen_encoding') })
          .onClick(() => menuBridge.reopenEncoding())
      }
      if (!menuBridge.showDocumentActions) {
        MenuItem({ content: $r('app.string.menu_save') })
          .onClick(() => menuBridge.save())
      }
      if (menuBridge.showDocumentActions) {
        MenuItem({ content: $r('app.string.menu_share') })
          .onClick(() => menuBridge.share())
        MenuItem({ content: menuBridge.favorite ? $r('app.string.menu_unfavorite') : $r('app.string.menu_favorite') })
          .onClick(() => menuBridge.toggleFavorite())
      }
    }
    MenuItemGroup() {
      MenuItem({ content: $r('app.string.menu_find') })
        .onClick(() => menuBridge.find())
      if (menuBridge.showCloseDocument) {
        MenuItem({ content: $r('app.string.menu_close') })
          .onClick(() => menuBridge.closeDocument())
      }
    }
    if (menuBridge.showDocumentActions) {
      MenuItemGroup() {
        MenuItem({ content: $r('app.string.menu_delete') })
          .enabled(menuBridge.canDeleteDocument)
          .onClick(() => menuBridge.deleteDocument())
      }
    }
    MenuItemGroup() {
      MenuItem({ content: $r('app.string.settings') })
        .onClick(() => menuBridge.openSettings())
    }
  }
}
