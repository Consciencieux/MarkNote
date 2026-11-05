import { DocumentFormat, FormatRegistry } from '../document/FormatRegistry';

/**
 * 菜单内容通过全局 @Builder 交给 ComponentContent 渲染，拿不到页面实例，所以用这个桥把
 * 点击转回页面：页面在 aboutToAppear 里接上自己的处理，菜单只负责发起动作。
 */
export class MenuBridge {
  confirmNew: (id: string) => void = (_id: string): void => {};
  openFile: () => void = (): void => {};
  saveAs: () => void = (): void => {};
  openSettings: () => void = (): void => {};
  showLegal: () => void = (): void => {};
  find: () => void = (): void => {};
  closeLibrary: () => void = (): void => {};
  /** 打开文稿页标题栏的菜单；锚点 id 由文稿页的标题栏提供。 */
  openDocumentMenu: () => void = (): void => {};
  /** 先收起已打开的菜单再执行动作，首页提供实现。 */
  dismiss: (next: () => void) => void = (next: () => void): void => next();
}

export const menuBridge: MenuBridge = new MenuBridge();

/** 首页标题栏的四宫格菜单：只有设置和关于。 */
@Builder
export function HomeMenuContent() {
  Menu() {
    MenuItemGroup() {
      MenuItem({ content: '设置' })
        .onClick(() => menuBridge.openSettings())
      MenuItem({ content: '关于' })
        .onClick(() => menuBridge.showLegal())
    }
  }
}

/** 文稿页标题栏的四宫格菜单：新建各格式、打开、另存为、查找和设置。 */
@Builder
export function DocumentMenuContent() {
  Menu() {
    MenuItemGroup() {
      ForEach(FormatRegistry.all(), (item: DocumentFormat) => {
        MenuItem({ content: item.moreTitle })
          .onClick(() => menuBridge.confirmNew(item.id))
      }, (item: DocumentFormat) => item.id)
    }
    MenuItemGroup() {
      MenuItem({ content: '打开文件' })
        .onClick(() => menuBridge.openFile())
      MenuItem({ content: '另存为' })
        .onClick(() => menuBridge.saveAs())
    }
    MenuItemGroup() {
      MenuItem({ content: '查找' })
        .onClick(() => menuBridge.find())
      MenuItem({ content: '返回文稿列表' })
        .onClick(() => menuBridge.closeLibrary())
    }
    MenuItemGroup() {
      MenuItem({ content: '设置' })
        .onClick(() => menuBridge.openSettings())
      MenuItem({ content: '关于' })
        .onClick(() => menuBridge.showLegal())
    }
  }
}
