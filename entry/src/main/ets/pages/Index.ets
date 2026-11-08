import { common, ConfigurationConstant, bundleManager } from '@kit.AbilityKit';
import {
  ColorMetrics, ComponentContent, mediaquery, SegmentButtonV2Items, TabSegmentButtonV2
} from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import {
  HdsNavigation, HdsNavigationTitleMode,
  HdsNavigationIconOptions, HdsNavigationMenuItemOptions,
  HdsNavigationTitleBarOptions, TitleBarContentOptions
} from '@kit.UIDesignKit';
import { RecentDocument } from '../model/Document';
import { DocumentService } from '../document/DocumentService';
import { sortRecentDocuments } from '../document/RecentOrder';
import { LaunchRequests, OpenRequest } from '../document/LaunchRequests';
import { HomeView } from './HomeView';
import { DocumentView } from './DocumentView';
import { SettingsPage } from './SettingsPage';
import { scrollingTitleBar } from './HdsMaterialStyles';
import { segmentButtonMaterial } from './ImmersiveMaterials';
import { menuMaterialOptions } from './MenuMaterialOptions';
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
  @State private projectLicenseText: string = '';
  @State private recents: RecentDocument[] = [];
  @State private sortOrder: string = 'modified';
  @State private theme: string = 'system';
  @State private version: string = '';
  @State private wide: boolean = false;
  @State private navigationMode: NavigationMode = NavigationMode.Stack;
  @State private documentExpanded: boolean = false;
  @State private documentOpen: boolean = false;
  /** 首页分段按钮：0 是全部，1 是收藏。 */
  @State private librarySegment: number = 0;
  private readonly librarySegmentItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '全部' }, { text: '收藏' }
  ]);
  private readonly librarySegmentMaterial = segmentButtonMaterial();
  /** 每开一篇加一，文稿页据此重新载入会话。 */
  @State private revision: number = 0;
  private context: common.UIAbilityContext | null = null;
  private routes: NavPathStack = new NavPathStack();
  private libraryScroller: Scroller = new Scroller();
  private wideQuery: mediaquery.MediaQueryListener | null = null;
  private homeMenu: ComponentContent<Object> | null = null;
  private documentMenu: ComponentContent<Object> | null = null;
  private recentTask: Promise<void> = Promise.resolve();

  aboutToAppear(): void {
    menuBridge.openFile = (): void => {
      this.afterMenu(() => this.confirmSwitch(() => this.pickOpen()));
    };
    menuBridge.openSettings = (): void => {
      this.afterMenu(() => {
        this.documentExpanded = false;
        this.routes.pushPathByName('settings', '');
      });
    };
    menuBridge.setSortOrder = (order: string): void => {
      this.afterMenu(() => {
        this.sortOrder = order;
        if (this.context) void LocalState.writeSort(this.context, order).catch(() => this.toast('排序方式保存失败'));
      });
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
      this.sortOrder = await LocalState.readSort(this.context);
      void this.refreshRecentTimes(this.recents);
      this.changeTheme(await LocalState.readTheme(this.context), false);
    } catch {
      this.toast('读取设置失败，已使用系统默认值');
    }
    LaunchRequests.bind((request: OpenRequest) => {
      this.confirmSwitch(() => this.openExternal(request));
    });
    await this.resumeDraft();
  }

  /** 版本号只读一次，供「关于」页显示；读取失败时由页面显示提示。 */
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
   * 分栏阈值使用 ArkUI 典型 WIDTH_LG 断点（API 枚举文档 ts-appendix-enums）：窗口宽度达到 840vp。
   * 监听仍由官方媒体查询 API 完成，避免在页面区域变化事件里自行计算宽度。
   */
  private bindWideBreakpoint(): void {
    this.wideQuery = this.getUIContext().getMediaQuery().matchMediaSync('(width >= 840vp)');
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
    // 只配必要的字段；isEnabled 默认 true、type 默认 IconStyleMode.NORMAL，不再重复写。
    // componentId 是 openMenu 的锚点 id（见《不依赖UI组件的全局菜单》），必须保留。
    const content: HdsNavigationIconOptions = {
      label: label,
      icon: symbol,
      action: action,
      componentId: id
    };
    const item: HdsNavigationMenuItemOptions = { content: content };
    return item;
  }

  @Builder
  private HomeSegment() {
    // 标题栏自定义区域按官方示例给两侧操作保留空间。
    // 150vp 是示例中的双选项宽度上限，空间不足时随容器收缩。
    Row() {
      Blank().width(40)
      Blank().width($r('sys.float.padding_level4'))
      Row() {
        Row() {
          TabSegmentButtonV2({
            items: this.librarySegmentItems,
            selectedIndex: this.librarySegment,
            $selectedIndex: (index: number): void => { this.librarySegment = index; },
            itemSelectedFontColor: ColorMetrics.resourceColor($r('sys.color.font_emphasize')),
            // 默认选中背景与强调文字在深色模式下对比不足；使用随主题变化的系统强调背景。
            // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ohos-arkui-advanced-segmentbuttonv2/
            itemSelectedBackgroundColor: ColorMetrics.resourceColor($r('sys.color.comp_emphasize_tertiary')),
            backgroundSystemMaterial: this.librarySegmentMaterial
          })
        }
        .width('100%')
        .constraintSize({ maxWidth: 150 })
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      Blank().width($r('sys.float.padding_level4'))
      Blank().width(40)
    }
    .width('100%')
    .padding({ left: $r('sys.float.margin_left'), right: $r('sys.float.margin_right') })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  private homeTitle(): HdsNavigationTitleBarOptions {
    // 《设置自定义区域》要求自定义节点不要挡住标题文字和菜单。
    const content: TitleBarContentOptions = {
      title: { mainTitle: '' },
      stackBuilder: (): void => { this.HomeSegment(); }
    };
    content.menu = {
      value: [
        this.menuIcon('更多', $r('sys.symbol.dot_grid_2x2'), 'marknote-home-more',
          (): void => this.openHomeMenu())
      ]
    };
    return scrollingTitleBar(content);
  }

  private openHomeMenu(): void {
    const uiContext = this.getUIContext();
    menuBridge.sortOrder = this.sortOrder;
    this.homeMenu = new ComponentContent<Object>(uiContext, wrapBuilder(HomeMenuContent));
    uiContext.getPromptAction().openMenu(this.homeMenu, { id: 'marknote-home-more' }, menuMaterialOptions()).catch(() => {
      // The menu stays closed when its anchor is not on screen.
    });
  }

  private openDocumentMenu(): void {
    const uiContext = this.getUIContext();
    menuBridge.showCloseDocument = this.navigationMode === NavigationMode.Split || this.documentExpanded;
    this.documentMenu = new ComponentContent<Object>(uiContext, wrapBuilder(DocumentMenuContent));
    uiContext.getPromptAction().openMenu(this.documentMenu, { id: 'marknote-doc-more' }, menuMaterialOptions()).catch(() => {
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
   * 将设置子页推入当前导航栈。
   * 许可证全文按需读一次，其余页面不碰磁盘。
   * 本项目许可证和第三方声明分开放，避免后打开的页面覆盖先打开的全文。
   */
  private openSetting(section: string): void {
    if (section === 'project-license' && this.projectLicenseText.length === 0) {
      this.projectLicenseText = this.readRawLicense('licenses/LICENSE', '未能读取本项目许可证。');
    }
    if (section === 'licenses' && this.legalText.length === 0) {
      this.legalText = this.readRawLicense('licenses/THIRD_PARTY_NOTICES.txt',
        '未能读取第三方许可证，请确保已运行 renderer 的构建命令。');
    }
    this.routes.pushPathByName(section, '');
  }

  /** 华为 FAQ faqs-ability-58：通过隐式 Want 打开默认浏览器。 */
  private openProjectHome(): void {
    if (!this.context) return;
    this.context.startAbility({
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: 'https://github.com/Consciencieux/MarkNote'
    }).catch(() => this.toast('无法打开项目主页'));
  }

  /** 华为《拉起邮件类应用（mailto方式）》：由邮件应用处理发送。 */
  private openFeedback(): void {
    if (!this.context) return;
    this.context.startAbility({
      action: 'ohos.want.action.sendToData',
      uri: 'mailto:zhouyi1227@outlook.com?subject=MarkNote%20Feedback'
    }).catch(() => this.toast('无法打开邮件应用，请发送至 zhouyi1227@outlook.com'));
  }

  private readRawLicense(path: string, failure: string): string {
    if (!this.context) return failure;
    try {
      const bytes = this.context.resourceManager.getRawFileContentSync(path);
      return util.TextDecoder.create('utf-8').decodeToString(bytes);
    } catch {
      return failure;
    }
  }

  /**
   * 切换文稿前由文稿页处理未保存的修改：有改动就先询问，不直接写回。首页只负责等结果。
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
    this.documentOpen = true;
    this.showDocumentRoute();
    const info = DocumentService.current().info;
    if (info.uri.length > 0 && info.persistent) this.rememberRecent(info.uri, info.name, true);
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
      // 华为《固定样式弹出框》：需要用户决定后续操作时使用警告弹窗。
      const fromFavorites = this.librarySegment === 1 && item.favorite === true;
      this.getUIContext().showAlertDialog({
        title: '无法打开文稿',
        message: fromFavorites ? '是否取消收藏？文件不会被删除。' :
          '是否从最近文稿中移除此记录？移除记录不会删除文件。',
        buttons: [
          {
            value: '保留',
            primary: true,
            action: (): void => {}
          },
          {
            value: '移除',
            action: (): void => {
              if (fromFavorites) this.toggleFavorite(item.uri, item.name);
              else void this.forgetRecent(item.uri);
            }
          }
        ]
      });
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

  private async forgetRecent(uri: string, deleted: boolean = false): Promise<void> {
    if (!this.context || uri.length === 0) return;
    try {
      const context = this.context;
      this.recentTask = this.recentTask.then(async (): Promise<void> => {
        this.recents = await LocalState.removeRecent(context, uri, this.recents, deleted);
        const retained = this.recents.some((item: RecentDocument): boolean => item.uri === uri);
        if (!retained && (!this.documentOpen || DocumentService.current().info.uri !== uri)) {
          await DocumentFiles.release(uri);
        }
      });
      await this.recentTask;
    } catch {
      this.recentTask = Promise.resolve();
      this.toast('最近文稿列表未能更新');
    }
  }

  private rememberRecent(uri: string, name: string, opened: boolean): void {
    if (!this.context || uri.length === 0) return;
    const context = this.context;
    this.recentTask = this.recentTask.then(async (): Promise<void> => {
      const modifiedAt = await DocumentFiles.recentModifiedAt(uri);
      this.recents = await LocalState.addRecent(context, uri, name, modifiedAt, opened, this.recents);
    }).catch((): void => {
      this.toast('最近文稿列表未能更新');
    });
  }

  private toggleFavorite(uri: string, name: string): void {
    if (!this.context || uri.length === 0) return;
    const context = this.context;
    this.recentTask = this.recentTask.then(async (): Promise<void> => {
      const modifiedAt = await DocumentFiles.recentModifiedAt(uri);
      this.recents = await LocalState.toggleFavorite(context, uri, name, modifiedAt, this.recents);
      const retained = this.recents.some((item: RecentDocument): boolean => item.uri === uri);
      if (!retained && (!this.documentOpen || DocumentService.current().info.uri !== uri)) {
        await DocumentFiles.release(uri);
      }
    }).catch((): void => this.toast('收藏状态保存失败'));
  }

  private async refreshRecentTimes(items: RecentDocument[]): Promise<void> {
    const refreshed: RecentDocument[] = [];
    for (const item of items) {
      const copy = new RecentDocument(item.uri, item.name);
      copy.openedAt = item.openedAt || 0;
      copy.modifiedAt = await DocumentFiles.recentModifiedAt(item.uri);
      copy.favorite = item.favorite === true;
      copy.recent = item.recent !== false;
      refreshed.push(copy);
    }
    const merged: RecentDocument[] = [];
    for (const current of this.recents) {
      const index = items.findIndex((item: RecentDocument): boolean => item.uri === current.uri);
      if (index >= 0 && items[index].name === current.name &&
        (items[index].openedAt || 0) === (current.openedAt || 0) &&
        (items[index].modifiedAt || 0) === (current.modifiedAt || 0) &&
        (items[index].favorite === true) === (current.favorite === true) &&
        (items[index].recent !== false) === (current.recent !== false)) {
        merged.push(refreshed[index]);
      } else {
        merged.push(current);
      }
    }
    this.recents = merged;
  }

  @Builder
  private LibraryPage() {
    HomeView({
      title: this.librarySegment === 1 ? '收藏' : '全部',
      favoritesOnly: this.librarySegment === 1,
      recents: sortRecentDocuments(this.recents.filter((item: RecentDocument): boolean =>
        this.librarySegment === 1 ? item.favorite === true : item.recent !== false), this.sortOrder) as RecentDocument[],
      scroller: this.libraryScroller,
      onNew: (id: string): void => { this.confirmSwitch(() => this.startNew(id)); },
      onOpen: (): void => this.confirmSwitch(() => this.pickOpen()),
      onRecent: (item: RecentDocument): void => this.openRecent(item),
      onRemoveRecent: (item: RecentDocument): void => {
        if (this.librarySegment === 1) {
          this.toggleFavorite(item.uri, item.name);
          return;
        }
        this.getUIContext().showAlertDialog({
          title: '移除记录',
          message: '从最近文稿中移除“' + item.name + '”？文件不会被删除。',
          buttons: [
            { value: '取消', action: (): void => {} },
            { value: '移除', action: (): void => { void this.forgetRecent(item.uri); } }
          ]
        });
      }
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
        canExpand: this.navigationMode === NavigationMode.Split || this.documentExpanded,
        expanded: this.documentExpanded,
        favorite: this.recents.some((item: RecentDocument): boolean =>
          item.uri === DocumentService.current().info.uri && item.favorite === true),
        onToggleExpanded: (): void => { this.documentExpanded = !this.documentExpanded; },
        revision: this.revision,
        onLeave: (): void => {
          const closed = DocumentService.current().info;
          this.documentExpanded = false;
          this.documentOpen = false;
          if (this.routes.size() > 0) this.routes.pop();
          // A removed record may still be in use by the open document until it is closed.
          if (closed.persistent && closed.uri.length > 0) {
            const uri = closed.uri;
            void this.recentTask.then((): void => {
              const listed = this.recents.some((item: RecentDocument): boolean => item.uri === uri);
              const inUse = this.documentOpen && DocumentService.current().info.uri === uri;
              if (!listed && !inUse) void DocumentFiles.release(uri);
            });
          }
        },
        onSaved: (uri: string, name: string): void => {
          this.rememberRecent(uri, name, false);
        },
        onDeleted: (uri: string): void => {
          void this.forgetRecent(uri, true);
        },
        onToggleFavorite: (uri: string, name: string): void => this.toggleFavorite(uri, name)
      })
    } else {
      SettingsPage({
        section: name,
        theme: $theme,
        version: this.version,
        text: name === 'project-license' ? this.projectLicenseText : this.legalText,
        onOpen: (section: string): void => this.openSetting(section),
        onOpenProject: (): void => this.openProjectHome(),
        onFeedback: (): void => this.openFeedback(),
        onBack: (): void => { this.routes.pop(); },
        onChooseTheme: (choice: string): void => this.changeTheme(choice)
      })
    }
  }

  build() {
    Column() {
      HdsNavigation(this.routes) {
        this.LibraryPage()
      }
      .navDestination(this.Destination)
      .titleBar(this.homeTitle())
      // HdsNavigationTitleMode.MINI 固定为 56vp（ui-design-hdsnavigation）。
      .titleMode(HdsNavigationTitleMode.MINI)
      // The official multi-device office example changes navigation mode to expand the content page.
      // https://developer.huawei.com/consumer/cn/doc/best-practices/multi-business-office/
      .mode(this.documentExpanded ? NavigationMode.Stack : NavigationMode.Auto)
      .onNavigationModeChange((mode: NavigationMode): void => { this.navigationMode = mode; })
      // 窗口宽度变化后交还给 Auto，避免手机单栏仍显示“恢复分栏”。
      .onAreaChange((oldArea: Area, newArea: Area) => {
        const oldWidth = Number(oldArea.width);
        const newWidth = Number(newArea.width);
        if (this.documentExpanded && oldWidth > 0 && newWidth > 0 && oldWidth !== newWidth) {
          this.documentExpanded = false;
        }
      })
      .hideBackButton(true)
      .bindToScrollable([this.libraryScroller])
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    // 页面底色只在这里给一次，整页（含标题栏所在区域）都是同一个系统底色。
    .backgroundColor($r('sys.color.ohos_id_color_background'))
  }
}
