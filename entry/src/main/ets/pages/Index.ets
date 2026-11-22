import { common, ConfigurationConstant, bundleManager } from '@kit.AbilityKit';
import {
  ColorMetrics, ComponentContent, ItemState, LengthMetrics, SegmentButtonV2Items, SymbolGlyphModifier,
  TabSegmentButtonV2, ToolBar, ToolBarOptions
} from '@kit.ArkUI';
import {
  HdsNavigation, HdsNavigationTitleMode,
  HdsNavigationTitleBarOptions, TitleBarContentOptions
} from '@kit.UIDesignKit';
import { RecentDocument, RecoveryData } from '../model/Document';
import { DocumentService, DocumentSession } from '../document/DocumentService';
import { StartupRecovery } from '../document/StartupRecovery';
import { sortRecentDocuments } from '../document/RecentOrder';
import { LaunchRequests, OpenRequest } from '../document/LaunchRequests';
import { HomeView } from './HomeView';
import { DocumentView } from './DocumentView';
import { SettingsPage } from './SettingsPage';
import { scrollingTitleBar, navigationMenuIcon } from './HdsMaterialStyles';
import { segmentButtonMaterial } from './ImmersiveMaterials';
import { menuMaterialOptions } from './MenuMaterialOptions';
import { chooseDocumentEncoding, DocumentMenuContent, HomeMenuContent, menuBridge } from './DocumentMenus';
import { documentBridge } from './DocumentBridge';
import { UnknownEncodingError } from '../storage/DocumentStream';
import { DocumentFiles } from '../storage/DocumentFiles';
import { DocumentShare, SharedFile } from '../document/DocumentShare';
import { LocalState } from '../storage/LocalState';
import { AppText } from '../i18n/AppText';
import { shownDetail } from '../document/UserNotice';
import { applyAppLanguage, isRightToLeftLanguage, normalizeAppLanguage, publishAppLanguage } from '../i18n/AppLanguage';

const SELECTION_MORE_ID = 'marknote-selection-more';

interface SelectionMoreOptions {
  onDelete: () => void;
}

@Builder
function SelectionMoreMenu(options: SelectionMoreOptions) {
  Menu() {
    MenuItem({ content: $r('app.string.delete_title'),
      symbolEndIcon: new SymbolGlyphModifier($r('sys.symbol.trash')).fontColor([$r('sys.color.warning')]) })
      .contentFontColor($r('sys.color.warning'))
      .onClick(options.onDelete)
  }
}

/**
 * 首页外壳：导航栈、主题、设置与关于，以及新建/打开/恢复的编排。
 * 文稿页自己的状态和保存逻辑在 DocumentView，两边通过 MenuBridge 和 DocumentBridge 通信。
 */
@Entry
@Component
struct Index {
  @State @Watch('refreshSelectionToolbar') private recents: RecentDocument[] = [];
  @State private sortOrder: string = 'modified';
  @State private theme: string = 'system';
  @State private language: string = 'default';
  @State private version: string = '';
  @State private navigationMode: NavigationMode = NavigationMode.Stack;
  @State private documentExpanded: boolean = false;
  @State private documentOpen: boolean = false;
  /** 首页分段按钮：0 是全部，1 是收藏。 */
  @State private librarySegment: number = 0;
  @State private selecting: boolean = false;
  @State @Watch('refreshSelectionToolbar') private selectedUris: string[] = [];
  @State private selectionToolbarItems: ToolBarOptions = new ToolBarOptions();
  private readonly librarySegmentItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: $r('app.string.home_all') },
    { text: $r('app.string.home_favorites_segment'), accessibilityText: $r('app.string.home_favorites') }
  ]);
  /** 用户改过语言后，启动时尚未返回的读取不能把选择盖回去。 */
  private languageEpoch: number = 0;
  private themeEpoch: number = 0;
  private sortEpoch: number = 0;
  private readonly librarySegmentMaterial = segmentButtonMaterial();
  /** 每开一篇加一，文稿页据此重新载入会话。 */
  @State private revision: number = 0;
  private context: common.UIAbilityContext | null = null;
  private routes: NavPathStack = new NavPathStack();
  private libraryScroller: Scroller = new Scroller();
  private homeMenu: ComponentContent<Object> | null = null;
  private documentMenu: ComponentContent<Object> | null = null;
  private recentTask: Promise<void> = Promise.resolve();
  /** 草稿恢复先入队，外部打开接在后面，避免两边同时替换会话。 */
  private openQueue: Promise<void> = Promise.resolve();
  private startupTask: Promise<void> = Promise.resolve();
  private recovery: StartupRecovery = new StartupRecovery((): Promise<boolean> => this.resumeDraft(),
    (_error: Error): void => {
      if (!this.disposed) this.toast($r('app.string.draft_read_failed'));
    });
  private externalWaiting: number = 0;
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.disposed = false;
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
        this.sortEpoch++;
        this.sortOrder = order;
        if (this.context) void LocalState.writeSort(this.context, order).catch(() => this.toast($r('app.string.sort_save_failed')));
      });
    };
    // 文稿页的标题栏菜单由这里打开：锚点 id 是全局的，菜单关闭也由这里统一收。
    menuBridge.openDocumentMenu = (): void => this.openDocumentMenu();
    menuBridge.dismiss = (next: () => void): void => this.afterMenu(next);
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (this.context) this.language = LocalState.readLanguageSync(this.context);
    AppStorage.setOrCreate('marknote_code_theme', this.context ? LocalState.readCodeThemeSync(this.context) : 'github');
    publishAppLanguage(this.language);
    this.startupTask = this.initialize();
  }

  aboutToDisappear(): void {
    this.disposed = true;
    LaunchRequests.unbind();
    documentBridge.cancelWait();
    this.releaseMenus();
  }

  onBackPress(): boolean {
    if (this.selecting && this.routes.size() === 0) {
      this.clearSelection();
      return true;
    }
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
    DocumentService.initializeRecovery(this.context);
    this.readVersion();
    const sortEpoch = this.sortEpoch;
    const themeEpoch = this.themeEpoch;
    try {
      this.recents = await LocalState.readRecent(this.context);
      const storedSort = await LocalState.readSort(this.context);
      if (!this.disposed && sortEpoch === this.sortEpoch) this.sortOrder = storedSort;
      void this.refreshRecentTimes(this.recents);
      const storedTheme = await LocalState.readTheme(this.context);
      if (!this.disposed && themeEpoch === this.themeEpoch) this.changeTheme(storedTheme, false);
      const languageEpoch = this.languageEpoch;
      const storedLanguage = await LocalState.readLanguage(this.context);
      if (!this.disposed && languageEpoch === this.languageEpoch) {
        this.language = storedLanguage;
        publishAppLanguage(storedLanguage);
      }
    } catch {
      this.toast($r('app.string.settings_read_failed'));
    }
    if (this.disposed) return;
    // 先开始恢复草稿，再接入外部打开。绑定若立刻交出暂存请求，也会排到恢复之后。
    this.openQueue = this.recovery.ensure().then((): void => {});
    LaunchRequests.bind((request: OpenRequest): void => this.enqueueExternal(request));
    await this.openQueue;
  }

  /** 外部打开一次只处理一个，并等上一次离开确认结束。 */
  private enqueueExternal(request: OpenRequest): void {
    this.externalWaiting++;
    this.openQueue = this.openQueue
      .catch((): void => {})
      .then(async (): Promise<void> => {
        try {
          await this.openAfterReady(request);
        } catch (error) {
          if (!this.disposed) this.toast(AppText.format($r('app.string.external_open_failed'), shownDetail(error)));
        } finally {
          this.externalWaiting--;
        }
      });
  }

  /**
   * 已有文稿时先确保文稿页显示并载入，再走离开确认。
   * 这样崩溃草稿不会在外部文件打开前被当成干净文稿清掉。
   */
  private async openAfterReady(request: OpenRequest): Promise<void> {
    if (this.disposed) return;
    if (!await this.recovery.ensure()) return;
    if (!await this.confirmLeaveIfOpen(true)) return;
    try {
      if (!this.disposed) await this.openExternal(request);
    } finally {
      documentBridge.resumeEditing();
    }
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
  private async resumeDraft(): Promise<boolean> {
    if (!this.context || this.disposed) return false;
    let draft: RecoveryData | null;
    try {
      draft = await LocalState.readDraft(this.context);
    } catch (error) {
      if (!LocalState.isInvalidDraft(error as Object)) throw error instanceof Error ? error : new Error('draft read failed');
      if (!await this.confirmDamagedDraft() || !this.context || this.disposed) return false;
      await LocalState.quarantineDraft(this.context);
      if (!this.disposed) this.toast($r('app.string.draft_corrupt_saved'));
      return !this.disposed;
    }
    if (draft === null) return true;
    if (!await DocumentService.restore(draft, (): boolean => !this.disposed)) {
      if (!this.disposed) throw new Error('draft restore blocked');
      return false;
    }
    if (this.disposed) return false;
    this.presentOpened();
    if (this.externalWaiting === 0) this.toast($r('app.string.draft_restored'));
    return true;
  }

  /** A damaged copy is kept separately only after the user chooses to continue. */
  private confirmDamagedDraft(): Promise<boolean> {
    return new Promise<boolean>((resolve: (accepted: boolean) => void): void => {
      let settled = false;
      const finish = (accepted: boolean): void => {
        if (settled) return;
        settled = true;
        resolve(accepted);
      };
      this.getUIContext().showAlertDialog({
        message: AppText.text($r('app.string.draft_corrupt_message')),
        autoCancel: true,
        buttonDirection: DialogButtonDirection.HORIZONTAL,
        buttons: [
          { value: AppText.text($r('app.string.dialog_cancel')), action: (): void => finish(false) },
          { value: AppText.text($r('app.string.draft_corrupt_keep')), primary: true, action: (): void => finish(true) }
        ],
        cancel: (): void => finish(false),
        onWillDismiss: (action: DismissDialogAction): void => {
          if (action.reason === DismissReason.PRESS_BACK || action.reason === DismissReason.TOUCH_OUTSIDE) {
            action.dismiss();
            finish(false);
          }
        }
      });
    });
  }

  private toast(message: string | Resource): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  private changeLanguage(choice: string): void {
    const next = normalizeAppLanguage(choice);
    if (next === this.language) return;
    const previous = this.language;
    this.languageEpoch++;
    if (this.context) {
      try {
        // 先落盘。系统若因语言变化重建页面，新页面会读到这次的选择，而不是上一种语言。
        LocalState.writeLanguageSync(this.context, next);
      } catch {
        this.toast($r('app.string.language_save_failed'));
        return;
      }
    }
    try {
      applyAppLanguage(next);
    } catch {
      if (this.context) {
        try {
          LocalState.writeLanguageSync(this.context, previous);
        } catch { /* 回滚失败时保留页面上原来的选择。 */ }
      }
      this.toast($r('app.string.language_save_failed'));
      return;
    }
    publishAppLanguage(next);
    this.language = next;
  }

  private changeTheme(choice: string, persist: boolean = true): void {
    if (persist) this.themeEpoch++;
    this.theme = choice;
    if (this.context) {
      let mode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      if (choice === 'light') mode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      if (choice === 'dark') mode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      this.context.getApplicationContext().setColorMode(mode);
      if (persist) {
        void LocalState.writeTheme(this.context, choice).catch(() => this.toast($r('app.string.theme_save_failed')));
      }
    }
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
            itemPadding: {
              top: LengthMetrics.resource($r('sys.float.padding_level2')),
              bottom: LengthMetrics.resource($r('sys.float.padding_level2')),
              start: LengthMetrics.resource($r('sys.float.padding_level2')),
              end: LengthMetrics.resource($r('sys.float.padding_level2'))
            },
            selectedIndex: this.librarySegment,
            $selectedIndex: (index: number): void => {
              if (this.librarySegment === index) return;
              this.clearSelection();
              this.librarySegment = index;
              this.libraryScroller.scrollTo({ xOffset: 0, yOffset: 0 });
            },
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
    // 镜像语言的左右间距用 start/end，RTL 时自动对调。
    // https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs/faqs-arkui-314
    .padding({
      start: LengthMetrics.resource($r('sys.float.margin_left')),
      end: LengthMetrics.resource($r('sys.float.margin_right'))
    })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  private homeTitle(): HdsNavigationTitleBarOptions {
    if (this.selecting) {
      const selected: TitleBarContentOptions = {
        title: {
          mainTitle: this.language.length >= 0 ?
            AppText.format($r('app.string.home_selected'), String(this.selectedUris.length)) : ''
        }
      };
      selected.menu = {
        value: [
          navigationMenuIcon($r('app.string.dialog_cancel'), $r('sys.symbol.xmark'), 'marknote-select-cancel',
            (): void => this.clearSelection())
        ]
      };
      return scrollingTitleBar(selected);
    }
    // 《设置自定义区域》要求自定义节点不要挡住标题文字和菜单。
    const content: TitleBarContentOptions = {
      title: { mainTitle: '' },
      stackBuilder: (): void => { this.HomeSegment(); }
    };
    content.menu = {
      value: [
        navigationMenuIcon($r('app.string.menu_more'), $r('sys.symbol.dot_grid_2x2'), 'marknote-home-more',
          (): void => this.openHomeMenu())
      ]
    };
    return scrollingTitleBar(content);
  }

  private openHomeMenu(): void {
    if (this.disposed || this.homeMenu !== null) return;
    const uiContext = this.getUIContext();
    menuBridge.sortOrder = this.sortOrder;
    const content = new ComponentContent<Object>(uiContext, wrapBuilder(HomeMenuContent));
    this.homeMenu = content;
    const options = menuMaterialOptions();
    options.onDidDisappear = (): void => this.disposeMenu(content, true);
    uiContext.getPromptAction().openMenu(content, { id: 'marknote-home-more' }, options)
      .catch((): void => this.disposeMenu(content, true));
  }

  private openDocumentMenu(): void {
    if (this.disposed || this.documentMenu !== null) return;
    const uiContext = this.getUIContext();
    menuBridge.showCloseDocument = this.navigationMode === NavigationMode.Split || this.documentExpanded;
    const content = new ComponentContent<Object>(uiContext, wrapBuilder(DocumentMenuContent));
    this.documentMenu = content;
    const options = menuMaterialOptions();
    options.onDidDisappear = (): void => this.disposeMenu(content, false);
    uiContext.getPromptAction().openMenu(content, { id: 'marknote-doc-more' }, options)
      .catch((): void => this.disposeMenu(content, false));
  }

  private disposeMenu(content: ComponentContent<Object>, home: boolean): void {
    // Both dismissal and an error can arrive. Release each native node only once.
    if (home ? this.homeMenu !== content : this.documentMenu !== content) return;
    if (home) this.homeMenu = null;
    else this.documentMenu = null;
    content.dispose();
  }

  private releaseMenus(): void {
    const prompt = this.getUIContext().getPromptAction();
    const home = this.homeMenu;
    const document = this.documentMenu;
    if (home !== null) {
      void prompt.closeMenu(home).then((): void => this.disposeMenu(home, true))
        .catch((): void => this.disposeMenu(home, true));
    }
    if (document !== null) {
      void prompt.closeMenu(document).then((): void => this.disposeMenu(document, false))
        .catch((): void => this.disposeMenu(document, false));
    }
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
   * 许可证页先进入，再由页面自己异步读取原文。
   */
  private openSetting(section: string): void {
    this.routes.pushPathByName(section, '');
  }

  /** 华为 FAQ faqs-ability-58：通过隐式 Want 打开默认浏览器。 */
  private openWebPage(uri: string, failureMessage: Resource): void {
    if (!this.context) return;
    this.context.startAbility({
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri
    }).catch(() => this.toast(failureMessage));
  }

  /** 华为《拉起邮件类应用（mailto方式）》：由邮件应用处理发送。 */
  private openFeedback(): void {
    if (!this.context) return;
    this.context.startAbility({
      action: 'ohos.want.action.sendToData',
      uri: 'mailto:zhouyi1227@outlook.com?subject=MarkNote%20Feedback'
    }).catch(() => this.toast($r('app.string.mail_open_failed')));
  }

  /**
   * 切换文稿前由文稿页处理未保存的修改：有改动就先询问，不直接写回。首页只负责等结果。
   */
  private confirmSwitch(proceed: () => Promise<void>): void {
    // Initialization installs draft recovery before any user-initiated switch joins the queue.
    void this.startupTask.then((): void => {
      this.openQueue = this.openQueue.catch((): void => {}).then(async (): Promise<void> => {
        if (this.disposed) return;
        if (!await this.recovery.ensure()) return;
        if (!await this.confirmLeaveIfOpen(false)) return;
        try {
          if (!this.disposed) await proceed();
        } finally {
          documentBridge.resumeEditing();
        }
      }).catch((error: Error): void => {
        if (!this.disposed) this.toast(AppText.format($r('app.string.open_failed'), shownDetail(error)));
      });
    }).catch((error: Error): void => {
      if (!this.disposed) this.toast(AppText.format($r('app.string.open_failed'), shownDetail(error)));
    });
  }

  /** 已打开文稿时先显示文稿页，再按离开规则确认。外部打开在页面不可见时提示；普通切换只停止。 */
  private async confirmLeaveIfOpen(requireVisible: boolean): Promise<boolean> {
    if (!this.documentOpen) return true;
    this.revealDocumentRoute();
    const visible = await documentBridge.whenVisible();
    if (this.disposed) return false;
    if (!visible) {
      if (requireVisible) this.toast($r('app.string.document_not_visible'));
      return false;
    }
    return documentBridge.saveBeforeLeaving();
  }

  private showDocumentRoute(): void {
    const names = this.routes.getAllPathName();
    for (let index = 0; index < names.length; index++) {
      if (names[index] === 'document') return;
    }
    this.routes.pushPathByName('document', '');
  }

  /** 外部文件到达时，设置页可能盖住文稿页；先回到文稿才能可靠地询问未保存修改。 */
  private revealDocumentRoute(): void {
    const names = this.routes.getAllPathName();
    if (!names.includes('document')) {
      // 会话存在却没有文稿路由时，丢弃设置页路由，再恢复文稿页。
      this.routes.clear();
      this.showDocumentRoute();
      return;
    }
    if (names[names.length - 1] !== 'document') this.routes.popToName('document');
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
    if (!await DocumentService.startNew(kind)) return;
    this.presentOpened();
  }

  private async pickOpen(): Promise<void> {
    if (!this.context) return;
    const owner = DocumentService.current();
    const approvedSource = owner.source;
    try {
      const uri = await DocumentFiles.chooseOpen(this.context);
      if (uri.length === 0) return;
      if (!await this.openApproved(uri, '', true, false, owner, approvedSource)) return;
      this.presentOpened();
    } catch (error) {
      this.toast(AppText.format($r('app.string.open_failed'), shownDetail(error)));
    }
  }

  private openRecent(item: RecentDocument): void {
    this.confirmSwitch(() => this.openStored(item));
  }

  private async openStored(item: RecentDocument): Promise<void> {
    try {
      if (!await this.openCurrent(item.uri, '', true, false)) return;
      this.presentOpened();
    } catch {
      // 华为《固定样式弹出框》：需要用户决定后续操作时使用警告弹窗。
      const fromFavorites = this.librarySegment === 1 && item.favorite === true;
      this.getUIContext().showAlertDialog({
        title: AppText.text($r('app.string.open_failed_title')),
        message: fromFavorites ? AppText.text($r('app.string.open_failed_unfavorite')) :
          AppText.text($r('app.string.open_failed_remove')),
        buttons: [
          {
            value: AppText.text($r('app.string.dialog_keep')),
            primary: true,
            action: (): void => {}
          },
          {
            value: AppText.text($r('app.string.dialog_remove')),
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
      if (!await this.openCurrent(request.uri, request.declaredType, writeRequested, true)) return;
      // 没有现有文稿时，不能把设置页留在新文稿的返回路径下面。
      if (!this.documentOpen) this.routes.clear();
      this.presentOpened();
    } catch (error) {
      this.toast(AppText.format($r('app.string.open_failed'), shownDetail(error)));
    }
  }

  /** 读取前记下用户同意离开时的会话和正文。读取期间正文变了，仍由 confirmPreparedOpen 再确认。 */
  private openCurrent(uri: string, declaredType: string, writeRequested: boolean,
    external: boolean): Promise<boolean> {
    const owner = DocumentService.current();
    return this.openApproved(uri, declaredType, writeRequested, external, owner, owner.source);
  }

  private async openApproved(uri: string, declaredType: string, writeRequested: boolean, external: boolean,
    owner: DocumentSession, approvedSource: string): Promise<boolean> {
    const confirm = (): Promise<boolean> => this.confirmPreparedOpen(owner, approvedSource);
    try {
      return await DocumentService.openUri(uri, declaredType, writeRequested, external, confirm);
    } catch (error) {
      if (!(error instanceof UnknownEncodingError)) throw error instanceof Error ? error : new Error('open failed');
      if (this.disposed || DocumentService.current() !== owner) return false;
      const encoding = await chooseDocumentEncoding(this.getUIContext());
      if (!encoding || this.disposed || DocumentService.current() !== owner) return false;
      return DocumentService.openUri(uri, declaredType, writeRequested, external, confirm, encoding);
    }
  }

  private async confirmPreparedOpen(owner: DocumentSession, approvedSource: string): Promise<boolean> {
    if (this.disposed || DocumentService.current() !== owner) return false;
    if (owner.source === approvedSource) return true;
    if (!owner.editing) return false;
    this.revealDocumentRoute();
    if (!await documentBridge.whenVisible()) return false;
    while (!this.disposed && DocumentService.current() === owner && owner.editing) {
      const source = owner.source;
      if (!await documentBridge.saveBeforeLeaving()) return false;
      if (DocumentService.current() === owner && owner.source === source) return true;
    }
    return false;
  }

  private async forgetRecent(uri: string, deleted: boolean = false): Promise<boolean> {
    if (!this.context || uri.length === 0) return false;
    try {
      const context = this.context;
      const task = this.recentTask.then(async (): Promise<void> => {
        this.recents = await LocalState.removeRecent(context, uri, this.recents, deleted);
        const retained = this.recents.some((item: RecentDocument): boolean => item.uri === uri);
        if (!retained && (!this.documentOpen || DocumentService.current().info.uri !== uri)) {
          await DocumentFiles.release(uri);
        }
      });
      this.recentTask = task.catch((): void => {});
      await task;
      return true;
    } catch {
      this.toast($r('app.string.recent_update_failed'));
      return false;
    }
  }

  private rememberRecent(uri: string, name: string, opened: boolean): void {
    if (!this.context || uri.length === 0) return;
    const context = this.context;
    this.recentTask = this.recentTask.then(async (): Promise<void> => {
      const modifiedAt = await DocumentFiles.recentModifiedAt(uri);
      this.recents = await LocalState.addRecent(context, uri, name, modifiedAt, opened, this.recents);
    }).catch((): void => {
      this.toast($r('app.string.recent_update_failed'));
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
    }).catch((): void => this.toast($r('app.string.favorite_save_failed')));
  }

  private listedRecents(): RecentDocument[] {
    return sortRecentDocuments(this.recents.filter((item: RecentDocument): boolean =>
      this.librarySegment === 1 ? item.favorite === true : item.recent !== false), this.sortOrder) as RecentDocument[];
  }

  private clearSelection(): void {
    this.selecting = false;
    this.selectedUris = [];
  }

  private beginSelection(item: RecentDocument): void {
    this.selecting = true;
    this.selectedUris = [item.uri];
  }

  private setSelectionMode(enabled: boolean): void {
    if (enabled) {
      this.selecting = true;
    } else {
      this.clearSelection();
    }
  }

  private setSelected(item: RecentDocument, selected: boolean): void {
    if (!this.selecting || this.selectedUris.includes(item.uri) === selected) return;
    this.selectedUris = selected ? [...this.selectedUris, item.uri] :
      this.selectedUris.filter((uri: string): boolean => uri !== item.uri);
  }

  private selectedItems(): RecentDocument[] {
    const visible = this.listedRecents();
    const picked: RecentDocument[] = [];
    for (let index = 0; index < this.selectedUris.length; index++) {
      const uri = this.selectedUris[index];
      for (let itemIndex = 0; itemIndex < visible.length; itemIndex++) {
        if (visible[itemIndex].uri === uri) picked.push(visible[itemIndex]);
      }
    }
    return picked;
  }

  private async shareRecents(items: RecentDocument[]): Promise<void> {
    if (!this.context || items.length === 0) return;
    const files: SharedFile[] = [];
    for (let index = 0; index < items.length; index++) {
      const file = new SharedFile();
      file.uri = items[index].uri;
      file.name = items[index].name;
      files.push(file);
    }
    try {
      await DocumentShare.showFiles(this.context, files, this.selecting ? 'marknote-home-share' : 'marknote-home-more');
    } catch (error) {
      this.toast(shownDetail(error));
    }
  }

  private async copyRecent(item: RecentDocument): Promise<void> {
    if (!this.context) return;
    try {
      const target = await DocumentFiles.chooseSave(this.context, item.name);
      if (target.length === 0 || this.disposed) return;
      if (target === item.uri) {
        this.toast($r('app.string.copy_same_file'));
        return;
      }
      await DocumentFiles.writeCopy(item.uri, target);
      const access = await DocumentFiles.prepare(target, true);
      if (access.persistent) this.rememberRecent(target, item.name, true);
      this.toast(access.persistent ? $r('app.string.copy_saved') : $r('app.string.save_not_persistent'));
    } catch (error) {
      this.toast(AppText.format($r('app.string.copy_failed'), shownDetail(error)));
    }
  }

  private confirmRemoveRecent(items: RecentDocument[]): void {
    if (items.length === 0) return;
    const message = items.length === 1 ?
      AppText.format($r('app.string.remove_recent_message'), items[0].name) :
      AppText.format($r('app.string.home_remove_many'), String(items.length));
    this.getUIContext().showAlertDialog({
      title: AppText.text($r('app.string.home_remove_record')),
      message: message,
      buttons: [
        { value: AppText.text($r('app.string.dialog_cancel')), action: (): void => {} },
        {
          value: AppText.text($r('app.string.dialog_remove')),
          action: (): void => { void this.removeRecents(items); }
        }
      ]
    });
  }

  private async removeRecents(items: RecentDocument[]): Promise<void> {
    for (const item of items) {
      if (await this.forgetRecent(item.uri)) this.setSelected(item, false);
    }
    if (this.selectedUris.length === 0) this.clearSelection();
  }

  private async confirmDeleteRecent(items: RecentDocument[]): Promise<void> {
    if (items.length === 0) return;
    const session = DocumentService.current();
    const uri = session.info.uri;
    if (this.documentOpen && session.editing && items.some((item: RecentDocument): boolean => item.uri === uri)) {
      if (await documentBridge.confirmDelete(uri, items.length)) {
        await this.deleteRecents(items.filter((item: RecentDocument): boolean => item.uri !== uri));
      }
      return;
    }
    const message = items.length === 1 ? AppText.text($r('app.string.delete_clean')) :
      AppText.format($r('app.string.home_delete_many'), String(items.length));
    this.getUIContext().showAlertDialog({
      title: AppText.text($r('app.string.delete_title')),
      message: message,
      buttons: [
        { value: AppText.text($r('app.string.dialog_cancel')), action: (): void => {} },
        {
          value: AppText.text($r('app.string.menu_delete')),
          action: (): void => { void this.deleteRecents(items); }
        }
      ]
    });
  }

  private async deleteRecents(items: RecentDocument[]): Promise<void> {
    let failed = false;
    let deleted = 0;
    for (const item of items) {
      // A document opened after the dialog appeared needs its own editor confirmation.
      const session = DocumentService.current();
      if (session.editing && session.info.uri === item.uri) {
        failed = true;
        continue;
      }
      try {
        await DocumentFiles.deleteStored(item.uri);
        await this.forgetRecent(item.uri, true);
        deleted++;
      } catch (error) {
        failed = true;
        this.toast(AppText.format($r('app.string.delete_failed'), shownDetail(error)));
      }
    }
    if (deleted > 0) this.toast($r('app.string.delete_trashed'));
    if (!failed) this.clearSelection();
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

  private refreshSelectionToolbar(): void {
    const actions = new ToolBarOptions();
    const state = this.selectedItems().length > 0 ? ItemState.ENABLE : ItemState.DISABLE;
    actions.push(
      {
        content: $r('app.string.menu_share'),
        toolBarSymbolOptions: {
          normal: new SymbolGlyphModifier($r('sys.symbol.share')).fontColor([$r('sys.color.icon_primary')])
        },
        state,
        action: (): void => { void this.shareRecents(this.selectedItems()); }
      },
      {
        content: $r('app.string.home_remove_record'),
        toolBarSymbolOptions: {
          normal: new SymbolGlyphModifier($r('sys.symbol.minus_circle')).fontColor([$r('sys.color.icon_primary')])
        },
        state,
        action: (): void => this.confirmRemoveRecent(this.selectedItems())
      },
      {
        content: $r('app.string.menu_more'),
        toolBarSymbolOptions: {
          normal: new SymbolGlyphModifier($r('sys.symbol.dot_grid_2x2'))
            .fontColor([$r('sys.color.icon_primary')])
            .id(SELECTION_MORE_ID)
        },
        state,
        action: (): void => this.openSelectionMoreMenu()
      }
    );
    this.selectionToolbarItems = actions;
  }

  private openSelectionMoreMenu(): void {
    if (this.disposed || this.homeMenu !== null || !this.selecting) return;
    const items = this.selectedItems();
    if (items.length === 0) return;
    const uiContext = this.getUIContext();
    const content = new ComponentContent<SelectionMoreOptions>(uiContext, wrapBuilder(SelectionMoreMenu), {
      onDelete: (): void => this.afterMenu(() => { void this.confirmDeleteRecent(items); })
    });
    this.homeMenu = content;
    const options = menuMaterialOptions();
    options.placement = Placement.Top;
    options.onDidDisappear = (): void => this.disposeMenu(content, true);
    uiContext.getPromptAction().openMenu(content, { id: SELECTION_MORE_ID }, options)
      .catch((): void => this.disposeMenu(content, true));
  }

  @Builder
  private SelectionToolbar() {
    Column() {
      ToolBar({ toolBarList: this.selectionToolbarItems })
    }
    .id('marknote-home-share')
  }

  @Builder
  private LibraryPage() {
    HomeView({
      favoritesOnly: this.librarySegment === 1,
      recents: this.listedRecents(),
      scroller: this.libraryScroller,
      selecting: this.selecting,
      selectedUris: this.selectedUris,
      onNew: (id: string): void => { this.confirmSwitch(() => this.startNew(id)); },
      onOpen: (): void => this.confirmSwitch(() => this.pickOpen()),
      onRecent: (item: RecentDocument): void => this.openRecent(item),
      onShare: (item: RecentDocument): void => { void this.shareRecents([item]); },
      onCopy: (item: RecentDocument): void => { void this.copyRecent(item); },
      onFavorite: (item: RecentDocument): void => this.toggleFavorite(item.uri, item.name),
      onRemove: (item: RecentDocument): void => this.confirmRemoveRecent([item]),
      onDelete: (item: RecentDocument): void => { void this.confirmDeleteRecent([item]); },
      onMultiSelect: (item: RecentDocument): void => this.beginSelection(item),
      onSelectionChange: (item: RecentDocument, selected: boolean): void => this.setSelected(item, selected),
      onEditModeChange: (enabled: boolean): void => this.setSelectionMode(enabled)
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
          this.routes.removeByName('document');
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
        onOpen: (section: string): void => this.openSetting(section),
        onOpenProject: (): void => this.openWebPage(
          'https://github.com/Consciencieux/MarkNote', $r('app.string.project_open_failed')),
        onOpenPrivacyPolicy: (): void => this.openWebPage(
          'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2079386824156960000',
          $r('app.string.privacy_open_failed')),
        onFeedback: (): void => this.openFeedback(),
        onBack: (): void => { this.routes.pop(); },
        onChooseTheme: (choice: string): void => this.changeTheme(choice),
        onChooseLanguage: (choice: string): void => this.changeLanguage(choice)
      })
    }
  }

  /**
   * 《如何实现镜像语言功能》：跟随系统时用 Direction.Auto，方向由系统语言决定。
   * 指定阿拉伯语或维吾尔语时改为从右向左，指定其他语言时改为从左向右。
   * https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs/faqs-arkui-556
   */
  private pageDirection(): Direction {
    if (this.language === 'default') return Direction.Auto;
    return isRightToLeftLanguage(this.language) ? Direction.Rtl : Direction.Ltr;
  }

  build() {
    Column() {
      HdsNavigation(this.routes) {
        this.LibraryPage()
      }
      .navDestination(this.Destination)
      .titleBar(this.homeTitle())
      .toolbarConfiguration(this.SelectionToolbar)
      .hideToolBar(!this.selecting)
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
    .direction(this.pageDirection())
    // 页面底色只在这里给一次，整页（含标题栏所在区域）都是同一个系统底色。
    .backgroundColor($r('sys.color.ohos_id_color_background'))
  }
}
