import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { ComponentContent, mediaquery } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import {
  HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, IconStyleMode, hdsMaterial,
  HdsNavigationTitle, HdsNavigationIconOptions, HdsNavigationMenuItemOptions,
  HdsNavigationMenuContentOptions, TitleBarContentOptions, TitleBarStyleOptions,
  HdsNavigationTitleBarOptions, ScrollEffectOptions, SystemMaterialParams
} from '@kit.UIDesignKit';
import { RecentDocument } from '../model/Document';
import { DocumentService } from '../document/DocumentService';
import { LaunchRequests, OpenRequest } from '../document/LaunchRequests';
import { HomeView } from './HomeView';
import { DocumentView } from './DocumentView';
import { LegalView } from './LegalView';
import { SettingsView, THEME_VALUES } from './SettingsView';
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
  @State private settingsOpen: boolean = false;
  @State private legalOpen: boolean = false;
  @State private legalText: string = '';
  @State private recents: RecentDocument[] = [];
  @State private theme: string = 'system';
  @State private themeSelected: number[] = [0];
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
      this.afterMenu(() => {
        this.legalOpen = false;
        this.settingsOpen = true;
      });
    };
    menuBridge.showLegal = (): void => {
      this.afterMenu(() => this.openLegal());
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
    if (this.settingsOpen) {
      this.settingsOpen = false;
      return true;
    }
    if (this.legalOpen) {
      this.legalOpen = false;
      return true;
    }
    if (this.routes.size() > 0) {
      this.leaveDocument();
      return true;
    }
    return false;
  }

  private async initialize(): Promise<void> {
    if (!this.context) return;
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
    this.themeSelected = [this.themeIndex()];
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

  /** Index of the current theme in THEME_VALUES, shared by the label table and the segmented control. */
  private themeIndex(): number {
    for (let index = 0; index < THEME_VALUES.length; index++) {
      if (THEME_VALUES[index] === this.theme) return index;
    }
    return 0;
  }

  private menuIcon(label: string, symbol: Resource, id: string, action: () => void,
    enabled: boolean = true): HdsNavigationMenuItemOptions {
    const content: HdsNavigationIconOptions = {
      label: label,
      icon: symbol,
      isEnabled: enabled,
      action: action,
      componentId: id,
      type: IconStyleMode.NORMAL
    };
    const item: HdsNavigationMenuItemOptions = { content: content };
    return item;
  }

  private titleStyle(scrolls: boolean): TitleBarStyleOptions {
    const scroll: ScrollEffectOptions = {
      enableScrollEffect: scrolls,
      scrollEffectType: ScrollEffectType.GRADIENT_BLUR
    };
    const material: SystemMaterialParams = {
      materialType: hdsMaterial.MaterialType.ADAPTIVE,
      materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
    };
    const style: TitleBarStyleOptions = {
      scrollEffectOpts: scroll,
      systemMaterialEffect: material
    };
    return style;
  }

  private homeTitle(): HdsNavigationTitleBarOptions {
    const heading: HdsNavigationTitle = { mainTitle: '文稿' };
    const menu: HdsNavigationMenuContentOptions = {
      value: [
        this.menuIcon('更多', $r('sys.symbol.dot_grid_2x2'), 'marknote-home-more', (): void => this.openHomeMenu())
      ]
    };
    const content: TitleBarContentOptions = { title: heading, menu: menu };
    const options: HdsNavigationTitleBarOptions = {
      enableComponentSafeArea: true,
      style: this.titleStyle(true),
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

  private openLegal(): void {
    if (!this.context) return;
    try {
      const bytes = this.context.resourceManager.getRawFileContentSync('licenses/THIRD_PARTY_NOTICES.txt');
      this.legalText = util.TextDecoder.create('utf-8').decodeToString(bytes);
    } catch {
      this.legalText = '未能读取第三方许可证，请确保已运行 renderer 的构建命令。';
    }
    this.settingsOpen = false;
    this.legalOpen = true;
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
    this.settingsOpen = false;
    this.legalOpen = false;
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
    }
  }

  @Builder
  private LegalPage() {
    LegalView({ text: this.legalText })
  }

  @Builder
  private SettingsPage() {
    // 选中态用 @Link 共享，页面切主题时设置里的高亮跟着变。
    SettingsView({
      selected: $themeSelected,
      onChoose: (choice: string): void => this.changeTheme(choice)
    })
  }

  build() {
    Column() {
      HdsNavigation(this.routes) {
        this.LibraryPage()
      }
      .navDestination(this.Destination)
      .titleBar(this.homeTitle())
      .titleMode(HdsNavigationTitleMode.FULL)
      .mode(NavigationMode.Stack)
      .hideBackButton(true)
      .bindToScrollable([this.libraryScroller])
      .bindSheet(this.legalOpen, this.LegalPage(), {
        title: { title: '关于' },
        showClose: true,
        height: SheetSize.LARGE,
        preferType: SheetType.BOTTOM,
        onDisappear: (): void => {
          this.legalOpen = false;
        }
      })
      .width('100%')
      .height('100%')
    }
    .bindSheet(this.settingsOpen, this.SettingsPage(), {
      title: { title: '设置' },
      showClose: true,
      height: SheetSize.FIT_CONTENT,
      preferType: SheetType.BOTTOM,
      onDisappear: (): void => {
        this.settingsOpen = false;
      }
    })
    .width('100%')
    .height('100%')
  }
}
