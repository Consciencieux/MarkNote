/**
 * 菜单内容通过全局 @Builder 交给 ComponentContent 渲染，拿不到页面实例，所以用这个桥把
 * 点击转回页面：页面在 aboutToAppear 里接上自己的处理，菜单只负责发起动作。
 */
export class MenuBridge {
  openFile: () => void = (): void => {};
  saveAs: () => void = (): void => {};
  share: () => void = (): void => {};
  deleteDocument: () => void = (): void => {};
  save: () => void = (): void => {};
  showDocumentActions: boolean = false;
  canDeleteDocument: boolean = false;
  openSettings: () => void = (): void => {};
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
 * 菜单里不再重复这两件事，只留页面上没有入口的「设置」。
 * 「关于」是设置页里的第二级入口，也不在这里。
 */
@Builder
export function HomeMenuContent() {
  Menu() {
    MenuItemGroup() {
      MenuItem({ content: '设置' })
        .onClick(() => menuBridge.openSettings())
    }
  }
}

/**
 * 使用 MenuItemGroup 按操作类型分组；具体项目和排序由应用功能决定。
 */
@Builder
export function DocumentMenuContent() {
  Menu() {
    MenuItemGroup() {
      MenuItem({ content: '打开文件' })
        .onClick(() => menuBridge.openFile())
      MenuItem({ content: '另存为' })
        .onClick(() => menuBridge.saveAs())
      if (!menuBridge.showDocumentActions) {
        MenuItem({ content: '保存' })
          .onClick(() => menuBridge.save())
      }
      if (menuBridge.showDocumentActions) {
        MenuItem({ content: '分享' })
          .onClick(() => menuBridge.share())
        MenuItem({ content: '收藏' })
          .enabled(false)
      }
    }
    MenuItemGroup() {
      MenuItem({ content: '查找' })
        .onClick(() => menuBridge.find())
      if (menuBridge.showCloseDocument) {
        MenuItem({ content: '关闭文稿' })
          .onClick(() => menuBridge.closeDocument())
      }
    }
    if (menuBridge.showDocumentActions) {
      MenuItemGroup() {
        MenuItem({ content: '删除' })
          .enabled(menuBridge.canDeleteDocument)
          .onClick(() => menuBridge.deleteDocument())
      }
    }
    MenuItemGroup() {
      MenuItem({ content: '设置' })
        .onClick(() => menuBridge.openSettings())
    }
  }
}
