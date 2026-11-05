import { common, ConfigurationConstant, bundleManager } from '@kit.AbilityKit';
import { ComponentContent, mediaquery } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import {
  HdsNavigation, HdsNavigationTitleMode, HdsNavDestination, HdsNavDestinationTitleMode,
  ScrollEffectType, IconStyleMode,
  HdsNavigationTitle, HdsNavigationIconOptions, HdsNavigationMenuItemOptions,
  HdsNavigationMenuContentOptions, TitleBarContentOptions, TitleBarStyleOptions,
  HdsNavigationTitleBarOptions, ScrollEffectOptions
} from '@kit.UIDesignKit';
import { RecentDocument } from '../model/Document';
import { DocumentService } from '../document/DocumentService';
import { LaunchRequests, OpenRequest } from '../document/LaunchRequests';
import { HomeView } from './HomeView';
import { DocumentView } from './DocumentView';
import { SettingsView, settingTitle } from './SettingsView';
import { SettingsDetail } from './SettingsDetail';
import { DocumentMenuContent, HomeMenuContent, menuBridge } from './DocumentMenus';
import { documentBridge } from './DocumentBridge';
import { DocumentFiles } from '../storage/DocumentFiles';
import { LocalState } from '../storage/LocalState';

/**
 * 首页外壳：导航栈、主题、设置与关于，以及新建/打开/恢复的编排。
 * 文稿页自己的状态和保存逻辑在 DocumentView，两边通过 MenuBridge 和 DocumentBridge 通信。
 */
@Entry
@Component
struct Index {
  @State private legalText: string = '';
  @State private recents: RecentDocument[] = [];
  @State private theme: string = 'system';
  @State private version: string = '';
  @State private wide: boolean = false;
  /** 每开一篇加一，文稿页据此重新载入会话。 */
  @State private revision: number = 0;
  private context: common.UIAbilityContext | null = null;
  private routes: NavPathStack = new NavPathStack();
  private libraryScroller: Scroller = new Scroller();
  private wideQuery: mediaquery.MediaQueryListener | null = null;
  private homeMenu: ComponentContent<Object> | null = null;
  private documentMenu: ComponentContent<Object> | null = null;

  aboutToAppear(): void {
    menuBridge.confirmNew = (id: string): void => {
      this.afterMenu(() => this.confirmSwitch(() => this.startNew(id)));
    };
    menuBridge.openFile = (): void => {
      this.afterMenu(() => this.confirmSwitch(() => this.pickOpen()));
    };
    menuBridge.openSettings = (): void => {
      this.afterMenu(() => this.routes.pushPathByName('settings', ''));
    };
    menuBridge.closeLibrary = (): void => {
      this.afterMenu(() => this.leaveDocument());
    };
    // 文稿页的标题栏菜单由这里打开：锚点 id 是全局的，菜单关闭也由这里统一收。
    menuBridge.openDocumentMenu = (): void => this.openDocumentMenu();
    menuBridge.dismiss = (next: () => void): void => this.afterMenu(next);
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.bindWideBreakpoint();
    void this.initialize();
  }

  aboutToDisappear(): void {
    LaunchRequests.unbind();
    if (this.wideQuery !== null) {
      this.wideQuery.off('change');
      this.wideQuery = null;
    }
  }

  onBackPress(): boolean {
    if (this.routes.size() > 0) {
      const names = this.routes.getAllPathName();
      const top = names.length > 0 ? names[names.length - 1] : '';
      if (top !== 'document') {
        // 设置首页和它的子页都属于普通页面，返回键直接退栈。
        this.routes.pop();
        return true;
      }
      this.leaveDocument();
      return true;
    }
    return false;
  }

  private async initialize(): Promise<void> {
    if (!this.context) return;
    this.readVersion();
    try {
      this.recents = await LocalState.readRecent(this.context);
      this.changeTheme(await LocalState.readTheme(this.context), false);
    } catch {
      this.toast('读取设置失败，已使用系统默认值');
    }
    LaunchRequests.bind((request: OpenRequest) => {
      this.confirmSwitch(() => this.openExternal(request));
    });
    await this.resumeDraft();
  }

  /** 版本号只读一次，设置里的「关于」行和「关于」页共用。读不到就留空，由界面自己省略。 */
  private readVersion(): void {
    try {
      this.version = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName;
    } catch {
      this.version = '';
    }
  }

  /**
   * 正常离开会清掉草稿，所以启动时还存在的草稿只可能是上次异常退出留下的。
   * 直接接着编辑，不再让用户去首页找一张恢复卡片。
   */
  private async resumeDraft(): Promise<void> {
    if (!this.context || this.routes.size() > 0) return;
    const draft = LocalState.readDraft(this.context);
    if (draft === null) return;
    try {
      await DocumentService.restore(draft);
      this.presentOpened();
      this.toast('已恢复上次未保存的编辑');
    } catch {
      if (this.context) LocalState.clearDraft(this.context);
      this.toast('上次的编辑无法恢复，已丢弃');
    }
  }

  /**
   * 分栏阈值用官方媒体查询监听窗口宽度，不再在 Tabs 的 onAreaChange 里自己算宽度。
   * 720vp 与系统推荐的横向断点一致。
   */
  private bindWideBreakpoint(): void {
    this.wideQuery = this.getUIContext().getMediaQuery().matchMediaSync('(width >= 720vp)');
    this.wide = this.wideQuery.matches;
    this.wideQuery.on('change', (result: mediaquery.MediaQueryResult) => {
      this.wide = result.matches;
    });
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  private changeTheme(choice: string, persist: boolean = true): void {
    this.theme = choice;
    if (this.context) {
      let mode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      if (choice === 'light') mode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      if (choice === 'dark') mode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      this.context.getApplicationContext().setColorMode(mode);
      if (persist) {
        void LocalState.writeTheme(this.context, choice).catch(() => this.toast('主题设置未能保存'));
      }
    }
  }

  private menuIcon(label: string, symbol: Resource, id: string,
    action: () => void): HdsNavigationMenuItemOptions {
    const content: HdsNavigationIconOptions = {
      label: label,
      icon: symbol,
      isEnabled: true,
      action: action,
      componentId: id,
      type: IconStyleMode.NORMAL
    };
    const item: HdsNavigationMenuItemOptions = { content: content };
    return item;
  }

  /**
   * 首页标题栏。按官方《开发实例》(ui-design-navigation-dynamic-blur-demo) 的一级页面写法：
   * `titleMode` 用 HdsNavigationTitleMode.MINI，标题与右侧菜单在同一行，
   * 模糊样式显式写 ScrollEffectType.COMMON_BLUR（该示例同样这么配置），
   * 文档对 COMMON_BLUR 的说明是「用于强调控件与内容的层级分隔……适用于非沉浸式场景」，
   * 其标题栏背景默认透明，和页面同一底色。
   * 不用 FULL/FREE 的大标题形态：那两种模式下标题单独排在菜单下面，不在同一行。
   */
  private homeTitle(): HdsNavigationTitleBarOptions {
    const heading: HdsNavigationTitle = { mainTitle: '全部' };
    const menu: HdsNavigationMenuContentOptions = {
      value: [
        this.menuIcon('更多', $r('sys.symbol.dot_grid_2x2'), 'marknote-home-more', (): void => this.openHomeMenu())
      ]
    };
    const scroll: ScrollEffectOptions = {
      enableScrollEffect: true,
      scrollEffectType: ScrollEffectType.COMMON_BLUR
    };
    const style: TitleBarStyleOptions = { scrollEffectOpts: scroll };
    const content: TitleBarContentOptions = { title: heading, menu: menu };
    const options: HdsNavigationTitleBarOptions = {
      enableComponentSafeArea: true,
      style: style,
      content: content
    };
    return options;
  }

  private openHomeMenu(): void {
    const uiContext = this.getUIContext();
    this.homeMenu = new ComponentContent<Object>(uiContext, wrapBuilder(HomeMenuContent));
    uiContext.getPromptAction().openMenu(this.homeMenu, { id: 'marknote-home-more' }).catch(() => {
      // The menu stays closed when its anchor is not on screen.
    });
  }

  private openDocumentMenu(): void {
    const uiContext = this.getUIContext();
    this.documentMenu = new ComponentContent<Object>(uiContext, wrapBuilder(DocumentMenuContent));
    uiContext.getPromptAction().openMenu(this.documentMenu, { id: 'marknote-doc-more' }).catch(() => {
      // The menu stays closed when its anchor is not on screen.
    });
  }

  private afterMenu(next: () => void): void {
    const prompt = this.getUIContext().getPromptAction();
    const closeOne = (menu: ComponentContent<Object> | null, done: () => void): void => {
      if (menu === null) {
        done();
        return;
      }
      prompt.closeMenu(menu).then(() => done()).catch(() => done());
    };
    closeOne(this.homeMenu, () => {
      closeOne(this.documentMenu, next);
    });
  }

  /**
   * 打开设置的二级页：推入设置自己的导航栈，子页从右侧滑入，半模态本身不收起。
   * 许可证全文按需读一次，其余页面不碰磁盘。
   */
  private openSetting(section: string): void {
    if (section === 'licenses' && this.legalText.length === 0) {
      if (!this.context) return;
      try {
        const bytes = this.context.resourceManager.getRawFileContentSync('licenses/THIRD_PARTY_NOTICES.txt');
        this.legalText = util.TextDecoder.create('utf-8').decodeToString(bytes);
      } catch {
        this.legalText = '未能读取第三方许可证，请确保已运行 renderer 的构建命令。';
      }
    }
    this.routes.pushPathByName(section, '');
  }

  /**
   * 切换文稿前的保存决策由文稿页决定：已保存过且有写权限的文件直接写回，不再询问；
   * 只有无法静默写入的情况才让用户选择。首页只负责等结果。
   */
  private confirmSwitch(proceed: () => Promise<void>): void {
    void documentBridge.saveBeforeLeaving().then((ok: boolean) => {
      if (ok) void proceed();
    });
  }

  private showDocumentRoute(): void {
    const names = this.routes.getAllPathName();
    for (let index = 0; index < names.length; index++) {
      if (names[index] === 'document') return;
    }
    this.routes.pushPathByName('document', '');
  }

  private leaveDocument(): void {
    if (this.routes.size() > 0) documentBridge.requestLeave();
  }

  /** 会话已经在 DocumentService 里了，这里只推进 revision 让文稿页重新载入。 */
  private presentOpened(): void {
    this.revision++;
    this.showDocumentRoute();
    const info = DocumentService.current().info;
    if (info.uri.length > 0) void this.rememberRecent(info.uri, info.name);
  }

  private async startNew(kind: string): Promise<void> {
    DocumentService.startNew(kind);
    this.presentOpened();
  }

  private async pickOpen(): Promise<void> {
    if (!this.context) return;
    try {
      const uri = await DocumentFiles.chooseOpen(this.context);
      if (uri.length === 0) return;
      await DocumentService.openUri(uri, '', true, false);
      this.presentOpened();
    } catch (error) {
      this.toast('打开失败：' + String(error));
    }
  }

  private openRecent(item: RecentDocument): void {
    this.confirmSwitch(() => this.openStored(item));
  }

  private async openStored(item: RecentDocument): Promise<void> {
    try {
      await DocumentService.openUri(item.uri, '', true, false);
      this.presentOpened();
    } catch {
      this.toast('原文件授权可能已经失效，请使用“打开”重新选取');
    }
  }

  private async openExternal(request: OpenRequest): Promise<void> {
    const writeRequested = request.writeGranted || !request.readGranted;
    try {
      await DocumentService.openUri(request.uri, request.declaredType, writeRequested, true);
      this.presentOpened();
    } catch (error) {
      this.toast('打开失败：' + String(error));
    }
  }

  private async rememberRecent(uri: string, name: string): Promise<void> {
    if (!this.context || uri.length === 0) return;
    const previous = this.recents;
    try {
      const items = await LocalState.addRecent(this.context, uri, name);
      this.recents = items;
      for (let index = 0; index < previous.length; index++) {
        const oldUri = previous[index].uri;
        let stillListed = false;
        for (let next = 0; next < items.length; next++) {
          if (items[next].uri === oldUri) stillListed = true;
        }
        if (!stillListed) void DocumentFiles.release(oldUri);
      }
    } catch {
      this.toast('最近文稿列表未能更新');
    }
  }

  @Builder
  private LibraryPage() {
    HomeView({
      recents: this.recents,
      scroller: this.libraryScroller,
      onNew: (id: string): void => { this.confirmSwitch(() => this.startNew(id)); },
      onOpen: (): void => this.confirmSwitch(() => this.pickOpen()),
      onRecent: (item: RecentDocument): void => this.openRecent(item)
    })
  }

  /**
   * 设置走全屏页面：官方《多设备设置界面》把设置拆成导航页和内容页两段，
   * 导航页用 HdsNavigation、内容页用 HdsNavDestination，标题栏都用小标题模式，
   * 跳转靠 NavPathStack。这里两类页面都推在同一个主栈里，返回键由导航组件给。
   *
   * 不用半模态：官方《绑定半模态页面》写的是「适用于展示简单的任务或信息面板」，
   * 设置这种带二级页的层级结构不属于这个场景；半模态和全屏页面混在一起，
   * 会出现从底部弹起却占满整屏的形态。
   */
  @Builder
  Destination(name: string, _pageInfos: Object) {
    if (name === 'document') {
      DocumentView({
        theme: this.theme,
        wide: this.wide,
        revision: this.revision,
        onLeave: (): void => {
          if (this.routes.size() > 0) this.routes.pop();
        },
        onSaved: (uri: string, name: string): void => {
          void this.rememberRecent(uri, name);
        }
      })
    } else if (name === 'settings') {
      HdsNavDestination() {
        SettingsView({
          theme: $theme,
          version: this.version,
          onOpen: (section: string): void => this.openSetting(section)
        })
      }
      .titleBar({
        // 标题栏是组件级安全区，内容区才会避让标题栏。
        enableComponentSafeArea: true,
        content: {
          title: { mainTitle: '设置' }
        }
      })
      .titleMode(HdsNavDestinationTitleMode.MINI)
    } else {
      HdsNavDestination() {
        SettingsDetail({
          section: name,
          theme: $theme,
          version: this.version,
          text: this.legalText,
          onChooseTheme: (choice: string): void => this.changeTheme(choice)
        })
      }
      .titleBar({
        enableComponentSafeArea: true,
        content: {
          title: { mainTitle: settingTitle(name) }
        }
      })
      .titleMode(HdsNavDestinationTitleMode.MINI)
    }
  }

  build() {
    Column() {
      HdsNavigation(this.routes) {
        this.LibraryPage()
      }
      .navDestination(this.Destination)
      .titleBar(this.homeTitle())
      // 一级页面用 MINI：标题栏固定 56vp，标题与右侧菜单同一行。
      // 依据是官方《开发实例》中首页的写法（同篇示例同时用 MINI + COMMON_BLUR）。
      .titleMode(HdsNavigationTitleMode.MINI)
      .mode(NavigationMode.Stack)
      .hideBackButton(true)
      .bindToScrollable([this.libraryScroller])
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
