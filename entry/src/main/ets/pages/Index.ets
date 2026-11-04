import { common, ConfigurationConstant } from '@kit.AbilityKit';
import {
  ComponentContent, ComposeListItem, IconType, mediaquery, SegmentButton, SegmentButtonItemTuple,
  SegmentButtonOptions, SubHeader, SymbolGlyphModifier
} from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import {
  HdsNavigation, HdsNavDestination, HdsNavigationTitleMode, HdsNavDestinationTitleMode,
  ScrollEffectType, IconStyleMode, hdsMaterial, HdsNavigationTitle, HdsNavigationIconOptions,
  HdsNavigationMenuItemOptions, HdsNavigationMenuContentOptions, TitleBarContentOptions,
  TitleBarStyleOptions, HdsNavigationTitleBarOptions, ScrollEffectOptions, SystemMaterialParams,
  HdsTabs, HdsTabsController, HdsTabsFloatingStyle
} from '@kit.UIDesignKit';
import { DocumentInfo, Heading, RecentDocument, RecoveryData, linesIn } from '../model/Document';
import { DocumentService } from '../document/DocumentService';
import { DocumentFormat, FormatRegistry, InsertAction } from '../document/FormatRegistry';
import { SearchHit, TextSearch } from '../document/TextSearch';
import { EditHistory, EditStep } from '../document/EditHistory';
import { LaunchRequests, OpenRequest } from '../document/LaunchRequests';
import { DocumentFiles } from '../storage/DocumentFiles';
import { LocalState } from '../storage/LocalState';

class MenuBridge {
  confirmNew: (id: string) => void = (_id: string): void => {};
  openFile: () => void = (): void => {};
  saveAs: () => void = (): void => {};
  openSettings: () => void = (): void => {};
  showLegal: () => void = (): void => {};
  find: () => void = (): void => {};
  closeLibrary: () => void = (): void => {};
}

const menuBridge: MenuBridge = new MenuBridge();

const THEME_VALUES: string[] = ['system', 'light', 'dark'];
const THEME_LABELS: string[] = ['跟随系统', '浅色', '深色'];
// 胶囊类单选分段按钮是官方给出的单选切换组件，选中态靠背景板高亮，不使用勾选图标。
const THEME_SEGMENTS: SegmentButtonOptions = SegmentButtonOptions.capsule({
  buttons: [
    { text: THEME_LABELS[0] }, { text: THEME_LABELS[1] }, { text: THEME_LABELS[2] }
  ] as SegmentButtonItemTuple,
  multiply: false
});

@Builder
function HomeMenuContent() {
  Menu() {
    MenuItemGroup() {
      MenuItem({ content: '设置' })
        .onClick(() => menuBridge.openSettings())
      MenuItem({ content: '关于' })
        .onClick(() => menuBridge.showLegal())
    }
  }
}

@Builder
function DocumentMenuContent() {
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

@Entry
@Component
struct Index {
  @State private editing: boolean = false;
  @State private settingsOpen: boolean = false;
  @State private legalOpen: boolean = false;
  @State private legalText: string = '';
  private preview: webview.WebviewController = new webview.WebviewController();
  private splitPreview: webview.WebviewController = new webview.WebviewController();
  private previewReady: boolean = false;
  private splitReady: boolean = false;
  private previewTimer: number = -1;
  @State private title: string = '未命名.md';
  @State private source: string = '';
  @State private savedText: string = '';
  @State private selectedTab: number = 0;
  @State private headings: Heading[] = [];
  @State private recents: RecentDocument[] = [];
  @State private theme: string = 'system';
  @State private themeSelected: number[] = [0];
  @State private saving: boolean = false;
  @State private wide: boolean = false;
  @State private searchVisible: boolean = false;
  @State private query: string = '';
  @State private replacement: string = '';
  @State private currentMatch: number = -1;
  /** Drives the enabled state of the title bar undo and redo icons. */
  @State private undoAvailable: boolean = false;
  @State private redoAvailable: boolean = false;
  /** True while the editor has focus, so the format bar can replace the tab bar. */
  @State private formatBarShown: boolean = false;
  private history: EditHistory = new EditHistory();
  private context: common.UIAbilityContext | null = null;
  private info: DocumentInfo = new DocumentInfo();
  private cursor: TextAreaController = new TextAreaController();
  private selectionStart: number = 0;
  private selectionEnd: number = 0;
  private recoveryTimer: number = -1;
  private routes: NavPathStack = new NavPathStack();
  private libraryScroller: Scroller = new Scroller();
  private wideQuery: mediaquery.MediaQueryListener | null = null;
  private materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.EXQUISITE;
  private homeMenu: ComponentContent<Object> | null = null;
  private documentMenu: ComponentContent<Object> | null = null;

  aboutToAppear(): void {
    menuBridge.confirmNew = (id: string): void => {
      this.afterMenu(() => this.confirmSwitch(() => this.startNew(id)));
    };
    menuBridge.openFile = (): void => {
      this.afterMenu(() => this.confirmSwitch(() => this.pickOpen()));
    };
    menuBridge.saveAs = (): void => {
      this.afterMenu(() => { void this.saveFile(true); });
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
    menuBridge.find = (): void => {
      this.afterMenu(() => {
        this.searchVisible = true;
        this.selectedTab = 0;
      });
    };
    menuBridge.closeLibrary = (): void => {
      this.afterMenu(() => this.leaveDocument());
    };
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.bindWideBreakpoint();
    this.pickMaterialLevel();
    void this.initialize();
  }

  /**
   * 设备不支持 IMMERSIVE 材质类型时降级到 SMOOTH，避免底部页签的沉浸光感拖慢低算力设备。
   * 判断方式取自官方沉浸光感示例。
   */
  private pickMaterialLevel(): void {
    let level = hdsMaterial.MaterialLevel.EXQUISITE;
    const types: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
    if (types.indexOf(hdsMaterial.MaterialType.IMMERSIVE) < 0) {
      level = hdsMaterial.MaterialLevel.SMOOTH;
    }
    this.materialLevel = level;
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
      if (!result.matches && this.selectedTab === this.splitTab()) this.selectedTab = 0;
    });
  }

  aboutToDisappear(): void {
    LaunchRequests.unbind();
    if (this.wideQuery !== null) {
      this.wideQuery.off('change');
      this.wideQuery = null;
    }
    this.flushRecovery();
    if (this.recoveryTimer >= 0) clearTimeout(this.recoveryTimer);
    if (this.previewTimer >= 0) clearTimeout(this.previewTimer);
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
      this.presentOpened(true);
      this.toast('已恢复上次未保存的编辑');
    } catch {
      this.clearRecovery();
      this.toast('上次的编辑无法恢复，已丢弃');
    }
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  private changeTheme(choice: string, persist: boolean = true): void {
    this.theme = choice;
    this.themeSelected = [this.themeIndex()];
    this.schedulePreview();
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

  private documentTitle(): HdsNavigationTitleBarOptions {
    const heading: HdsNavigationTitle = { mainTitle: this.title, subTitle: this.statusLine() };
    const menu: HdsNavigationMenuContentOptions = {
      maxCount: 4,
      value: [
        // 系统「备忘录」编辑态的标题栏右侧依次是撤销、重做、四宫格和纯勾（无圆圈），
        // 这里跟随同一排列。查找不是高频动作，收进四宫格菜单，把位置让给撤销和重做。
        this.menuIcon('撤销', $r('sys.symbol.undo'), 'marknote-undo',
          (): void => this.undo(), this.undoAvailable),
        this.menuIcon('重做', $r('sys.symbol.redo'), 'marknote-redo',
          (): void => this.redo(), this.redoAvailable),
        this.menuIcon('更多', $r('sys.symbol.dot_grid_2x2'), 'marknote-doc-more',
          (): void => this.openDocumentMenu()),
        this.menuIcon('保存', $r('sys.symbol.checkmark'), 'marknote-save',
          (): void => { void this.saveFile(false); })
      ]
    };
    const content: TitleBarContentOptions = { title: heading, menu: menu };
    const options: HdsNavigationTitleBarOptions = {
      enableComponentSafeArea: true,
      style: this.titleStyle(false),
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

  private schedulePreview(): void {
    if (this.previewTimer >= 0) clearTimeout(this.previewTimer);
    this.previewTimer = setTimeout(() => {
      this.previewTimer = -1;
      if (this.previewReady) this.sendPreview(this.preview);
      if (this.splitReady) this.sendPreview(this.splitPreview);
    }, 120);
  }

  private currentFormat(): DocumentFormat {
    return DocumentService.formatFor(this.info);
  }

  private previewIsDark(): boolean {
    if (this.theme === 'dark') return true;
    if (this.theme === 'light') return false;
    return this.context?.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  /** Index of the current theme in THEME_VALUES, shared by the label table and the segmented control. */
  private themeIndex(): number {
    for (let index = 0; index < THEME_VALUES.length; index++) {
      if (THEME_VALUES[index] === this.theme) return index;
    }
    return 0;
  }

  private sendPreview(controller: webview.WebviewController): void {
    const kind = this.currentFormat().id;
    const theme = this.previewIsDark() ? 'dark' : (this.theme === 'light' ? 'light' : 'system');
    const command = 'window.MarknotePreview.update(' + JSON.stringify({
      kind: kind,
      source: this.source,
      theme: theme
    }) + ')';
    try {
      controller.runJavaScript(command);
    } catch {
      // The Web surface may have been disposed while switching tabs.
    }
  }

  private isDirty(): boolean {
    return this.source !== this.savedText;
  }

  /**
   * 切换文稿前的保存决策，规则参考各平台编辑器的通行做法：
   * 已保存过且有写权限的文件直接写回，不再询问；只有无法静默写入的情况才让用户选择，
   * 也就是新建文稿还没有文件名、文件只读，或写回失败。
   * 草稿副本只用于崩溃兜底，不再作为「未保存」的常驻入口。
   */
  private async saveBeforeLeaving(): Promise<boolean> {
    if (!this.editing || !this.isDirty()) return true;
    const canWriteInPlace = this.info.uri.length > 0 && this.info.writable;
    if (canWriteInPlace && await this.saveFile(false)) return true;
    return await this.askSaveOrDiscard();
  }

  /** true 表示可以离开；保存过程中取消或失败都留在当前文稿。 */
  private async askSaveOrDiscard(): Promise<boolean> {
    // The reason matters: an unnamed document needs a name, a read-only one needs another
    // location, and a failed write may be an external modification.
    let message = '这份文稿没能写回原文件。可以先另存为，也可以放弃修改。';
    let saveLabel = '另存为';
    if (this.info.uri.length === 0) {
      message = '这份文稿还没有保存到文件。可以先保存，也可以放弃修改。';
      saveLabel = '保存';
    } else if (!this.info.writable) {
      message = '这个文件没有写入权限。可以另存为新文件，也可以放弃修改。';
    }
    let choice = -1;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '未保存的修改',
        message: message,
        buttons: [
          { text: saveLabel, color: $r('sys.color.font_primary') },
          { text: '放弃修改', color: $r('sys.color.font_secondary') },
          { text: '取消', color: $r('sys.color.font_secondary') }
        ]
      });
      choice = result.index;
    } catch {
      // 关闭对话框按取消处理，留在当前文稿。
    }
    if (choice === 0) return await this.saveFile(this.info.uri.length > 0 && !this.info.writable);
    return choice === 1;
  }

  /** 统一入口：新建、打开和切换文稿都先经过这里。 */
  private confirmSwitch(proceed: () => Promise<void>): void {
    void this.saveBeforeLeaving().then((ok: boolean) => {
      if (ok) void proceed();
    });
  }

  private syncFromService(): void {
    const session = DocumentService.current();
    this.info = session.info;
    this.title = session.info.name;
    this.source = session.source;
    this.savedText = session.savedText;
    this.editing = session.editing;
    this.headings = DocumentService.headingsFor(this.info, this.source);
    this.schedulePreview();
  }

  private showDocumentRoute(): void {
    const names = this.routes.getAllPathName();
    for (let index = 0; index < names.length; index++) {
      if (names[index] === 'document') return;
    }
    this.routes.pushPathByName('document', '');
  }

  private leaveDocument(): void {
    void this.closeToLibrary().then((left: boolean) => {
      if (left && this.routes.size() > 0) this.routes.pop();
    });
  }

  private presentOpened(keepDraft: boolean = false): void {
    this.syncFromService();
    // The history belongs to one document. Keeping it across a switch would let undo write
    // the previous document's text into this one.
    this.history.reset(this.source, 0);
    this.refreshHistoryState();
    this.currentMatch = -1;
    this.selectionStart = 0;
    this.selectionEnd = 0;
    this.selectedTab = 0;
    this.searchVisible = false;
    this.settingsOpen = false;
    this.legalOpen = false;
    // A recovered draft must stay on disk until it is saved or the user leaves normally.
    // Clearing it here would lose the restored text if the app dies again before an edit.
    if (keepDraft) this.flushRecovery();
    else this.clearRecovery();
    this.showDocumentRoute();
    if (this.info.uri.length > 0) void this.rememberRecent(this.info.uri, this.info.name);
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

  private async saveFile(asNewFile: boolean): Promise<boolean> {
    if (!this.context || !this.editing || this.saving) return false;
    this.saving = true;
    try {
      const result = await DocumentService.save(this.context, asNewFile);
      this.syncFromService();
      if (!result.saved) return false;
      this.toast(result.message);
      if (!this.isDirty()) this.clearRecovery();
      else this.scheduleRecovery();
      await this.rememberRecent(this.info.uri, this.title);
      return !result.stillDirty;
    } catch (error) {
      this.scheduleRecovery();
      this.toast('保存失败：' + String(error));
      return false;
    } finally {
      this.saving = false;
    }
  }

  private clearRecovery(): void {
    if (this.recoveryTimer >= 0) {
      clearTimeout(this.recoveryTimer);
      this.recoveryTimer = -1;
    }
    if (this.context) LocalState.clearDraft(this.context);
  }

  private scheduleRecovery(): void {
    if (this.recoveryTimer >= 0) clearTimeout(this.recoveryTimer);
    this.recoveryTimer = setTimeout(() => this.flushRecovery(), 450);
  }

  private flushRecovery(): void {
    this.recoveryTimer = -1;
    if (!this.context || !this.editing) return;
    if (!this.isDirty()) {
      this.clearRecovery();
      return;
    }
    const draft = new RecoveryData();
    draft.name = this.title;
    draft.uri = this.info.uri;
    draft.text = this.source;
    draft.savedText = this.savedText;
    draft.newline = this.info.newline;
    draft.lineEndings = this.info.lineEndings;
    draft.encoding = this.info.encoding;
    draft.hasBom = this.info.hasBom;
    draft.fingerprint = this.info.fingerprint;
    draft.formatId = this.info.formatId;
    draft.writable = this.info.writable;
    draft.persistent = this.info.persistent;
    try {
      LocalState.writeDraft(this.context, draft);
    } catch {
      this.toast('草稿恢复副本写入失败，请尽快保存文件');
    }
  }

  /**
   * 离开文稿：先按规则处理未保存的改动，再清掉草稿副本。
   * 返回 false 表示用户取消了离开，调用方不应弹栈。
   */
  private async closeToLibrary(): Promise<boolean> {
    if (!await this.saveBeforeLeaving()) return false;
    this.clearRecovery();
    DocumentService.close();
    this.editing = false;
    this.settingsOpen = false;
    return true;
  }

  /**
   * Every edit to the buffer goes through here, including the toolbar inserts and replace,
   * so undo covers them as well as typing.
   */
  private updateSource(text: string, caret: number = -1): void {
    DocumentService.edit(text);
    this.source = text;
    this.currentMatch = -1;
    this.headings = DocumentService.headingsFor(this.info, text);
    const position = caret >= 0 ? caret : this.selectionEnd;
    this.history.record(text, position, Date.now());
    this.refreshHistoryState();
    this.scheduleRecovery();
    this.schedulePreview();
  }

  private refreshHistoryState(): void {
    this.undoAvailable = this.history.canUndo();
    this.redoAvailable = this.history.canRedo();
  }

  private undo(): void {
    const step: EditStep | null = this.history.undo(this.selectionEnd);
    if (step === null) return;
    this.applyHistoryStep(step);
  }

  private redo(): void {
    const step: EditStep | null = this.history.redo(this.selectionEnd);
    if (step === null) return;
    this.applyHistoryStep(step);
  }

  /**
   * Restore a snapshot without recording it again, otherwise every undo would push a new step.
   */
  private applyHistoryStep(step: EditStep): void {
    DocumentService.edit(step.text);
    this.source = step.text;
    this.currentMatch = -1;
    this.headings = DocumentService.headingsFor(this.info, step.text);
    this.refreshHistoryState();
    this.scheduleRecovery();
    this.schedulePreview();
    const caret = Math.min(step.caret, step.text.length);
    this.selectionStart = caret;
    this.selectionEnd = caret;
    setTimeout(() => this.cursor.caretPosition(caret), 20);
  }

  private findNext(): void {
    if (!this.query) return;
    this.selectedTab = 0;
    const hit: SearchHit | null = TextSearch.following(this.source, this.query, this.currentMatch);
    if (hit === null) {
      this.currentMatch = -1;
      this.toast('没有找到匹配内容');
      return;
    }
    this.currentMatch = hit.start;
    setTimeout(() => this.cursor.setTextSelection(hit.start, hit.start + hit.length), 20);
  }

  private replaceMatch(): void {
    if (!this.query) return;
    const changed: string | null =
      TextSearch.replaceAt(this.source, this.currentMatch, this.query, this.replacement);
    if (changed === null) {
      this.findNext();
      return;
    }
    const caret = this.currentMatch + this.replacement.length;
    this.updateSource(changed, caret);
    this.currentMatch = -1;
    setTimeout(() => this.cursor.caretPosition(caret), 20);
  }

  private insertToken(action: InsertAction): void {
    const start = Math.min(this.selectionStart, this.selectionEnd);
    const end = Math.max(this.selectionStart, this.selectionEnd);
    const selected = this.source.slice(start, end);
    const changed = this.source.slice(0, start) + action.before + selected + action.after +
      this.source.slice(end);
    const position = start + action.before.length + selected.length;
    this.updateSource(changed, position);
    setTimeout(() => this.cursor.caretPosition(position), 20);
  }

  private focusHeading(heading: Heading): void {
    this.selectedTab = 0;
    setTimeout(() => this.cursor.caretPosition(heading.offset), 20);
  }

  private statusLine(): string {
    const count = `${linesIn(this.source)} 行 · ${this.source.length} 字符`;
    if (this.saving) return `${count} · 正在保存…`;
    if (this.isDirty() || this.info.uri.length === 0) return `${count} · 未保存`;
    if (!this.info.writable) return `${count} · 只读`;
    return `${count} · 已保存`;
  }

  private newDocumentMenu(): MenuElement[] {
    const items: MenuElement[] = [];
    const formats = FormatRegistry.all();
    for (let index = 0; index < formats.length; index++) {
      const format = formats[index];
      items.push({
        value: format.sheetTitle,
        action: (): void => { this.confirmSwitch(() => this.startNew(format.id)); }
      });
    }
    return items;
  }

  @Builder
  RecentHeader() {
    SubHeader({ primaryTitle: '最近文稿' })
  }

  /**
   * 列表行使用官方 ComposeListItem：图标尺寸、主副标题字号和行高都由组件按系统规范给出，
   * 不再手写 Row + SymbolGlyph + 两行 Text 和自行计算的 padding。
   */
  @Builder
  DocumentRow(title: string, detail: string, symbol: Resource) {
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
  RecentRow(item: RecentDocument) {
    ListItem() {
      this.DocumentRow(item.name, FormatRegistry.byFilename(item.name).sheetTitle, $r('sys.symbol.doc_text'))
    }
    .onClick(() => this.openRecent(item))
  }

  @Builder
  private LibraryPage() {
    // 卡片分组之间没有默认间隔：ListItemGroup 的 space 只作用于组内 ListItem，
    // 组与组的间隔由 List({ space }) 给出。12vp 与卡片自身的左右外边距一致。
    List({ scroller: this.libraryScroller, space: 12 }) {
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
              .onClick(() => this.confirmSwitch(() => this.pickOpen()))
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

  /**
   * 查找栏用官方 Search 的 searchButton 承载「下一处」，onSubmit 与按钮点击共用同一入口，
   * 不再在 Search 旁边另放一个文字按钮。关闭用系统符号的文本按钮。
   */
  @Builder
  private FindBar() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Search({ value: this.query, placeholder: '查找文稿内容' })
          .searchButton('下一处')
          .onSubmit(() => this.findNext())
          .onChange((value: string) => { this.query = value; this.currentMatch = -1; })
          .layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize($r('sys.float.ohos_id_text_size_body1'))
            .fontColor([$r('sys.color.font_primary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .accessibilityText('关闭查找')
        .onClick(() => this.searchVisible = false)
      }
      .width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.replacement, placeholder: '替换为' })
          .onChange((value: string) => { this.replacement = value; })
          .layoutWeight(1)
        Button('替换')
          .onClick(() => this.replaceMatch())
      }
      .width('100%')
    }
    .padding({
      left: $r('sys.float.margin_left'),
      right: $r('sys.float.margin_right'),
      top: 8,
      bottom: 8
    })
    .width('100%')
  }

  @Builder
  private EditPage() {
    Column() {
      if (this.searchVisible) {
        this.FindBar()
      }
      TextArea({ text: this.source, placeholder: '在这里开始写作…', controller: this.cursor })
        .fontSize($r('sys.float.ohos_id_text_size_body1'))
        .fontFamily('monospace')
        .width('100%')
        .layoutWeight(1)
        .onFocus(() => { this.formatBarShown = true; })
        .onBlur(() => { this.formatBarShown = false; })
        .onChange((value: string) => this.updateSource(value))
        .onTextSelectionChange((start: number, end: number) => {
          this.selectionStart = start;
          this.selectionEnd = end;
        })
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 编辑页、预览页和分栏共用同一个本地预览页面，差异只有 Web 控制器和就绪标记。
   * 合成一个构建器，避免三份重复的 Web 配置发生漂移。
   */
  @Builder
  private PreviewWeb(controller: webview.WebviewController, onReady: () => void) {
    Web({ src: $rawfile('preview/index.html'), controller: controller })
      .javaScriptAccess(true)
      .domStorageAccess(false)
      .backgroundColor(this.previewIsDark() ? '#000000' : '#FFFFFF')
      .onPageEnd(() => {
        onReady();
        this.sendPreview(controller);
      })
      .width('100%')
      .height('100%')
  }

  @Builder
  private PreviewPage() {
    this.PreviewWeb(this.preview, () => { this.previewReady = true; })
  }

  @Builder
  private SplitPreviewPage() {
    this.PreviewWeb(this.splitPreview, () => { this.splitReady = true; })
  }

  @Builder
  private LegalPage() {
    Scroll() {
      Column({ space: 12 }) {
        SubHeader({ primaryTitle: '隐私说明' })
        Text('文稿在设备本地编辑。应用没有账号、广告、遥测或联网接口，也不上传文稿。文件由系统文件选择器授权，草稿保存在应用私有目录。')
          .fontSize($r('sys.float.ohos_id_text_size_body1'))
          .padding({ left: 16, right: 16 })
        SubHeader({ primaryTitle: '第三方开源许可证' })
        Text(this.legalText)
          .fontSize($r('sys.float.ohos_id_text_size_body2'))
          .fontFamily('monospace')
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 24 })
          .copyOption(CopyOptions.LocalDevice)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .edgeEffect(EdgeEffect.Spring)
  }

  /**
   * 「外观」是单选设置项，用官方胶囊类单选分段按钮表达选中态。
   * 分组标题用官方 SubHeader，内容左右边距取系统设计变量，不再手写行高和勾选图标。
   */
  @Builder
  private SettingsPage() {
    Column() {
      SubHeader({ primaryTitle: '外观' })
      SegmentButton({
        options: THEME_SEGMENTS,
        selectedIndexes: $themeSelected,
        onItemClicked: (index: number) => this.changeTheme(THEME_VALUES[index])
      })
        .padding({ left: $r('sys.float.margin_left'), right: $r('sys.float.margin_right') })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 大纲是只读的扁平标题列表，层级只用于缩进，没有折叠和重命名。
   * 官方的 TreeView 面向带目录图标、增删改入口的文件树，套在这里会多出用不到的操作，
   * 因此沿用 List 承载，行内容用系统字号和颜色变量。
   */
  @Builder
  private OutlinePage() {
    if (this.headings.length === 0) {
      Column({ space: 10 }) {
        Text('暂无大纲').fontSize($r('sys.float.ohos_id_text_size_body1'))
        Text('在编辑页使用 #、## 等 Markdown 标题语法即可生成大纲。')
          .fontColor($r('sys.color.font_secondary'))
      }
      .padding(24)
      .width('100%')
    } else {
      List() {
        ForEach(this.headings, (heading: Heading) => {
          ListItem() {
            Row({ space: 8 }) {
              Text(heading.text)
                .fontSize($r('sys.float.ohos_id_text_size_body1'))
                .maxLines(2)
                .layoutWeight(1)
              Text(`第 ${heading.line} 行`)
                .fontSize($r('sys.float.ohos_id_text_size_body2'))
                .fontColor($r('sys.color.font_secondary'))
            }
            .padding({ left: 16 + (heading.level - 1) * 12, right: 16, top: 14, bottom: 14 })
            .width('100%')
            .onClick(() => this.focusHeading(heading))
          }
        }, (heading: Heading) => heading.offset.toString())
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
      .divider({ strokeWidth: 1, startMargin: 16, endMargin: 16 })
    }
  }

  private splitTab(): number {
    return this.currentFormat().outline ? 3 : 2;
  }

  /** 页签图标沿用系统符号，选中态由系统页签样式给出。 */
  private tabSymbol(symbol: Resource): TabBarSymbol {
    return { normal: new SymbolGlyphModifier(symbol) };
  }

  @Builder
  private SplitPage() {
    Row() {
      Column() { this.EditPage() }
        .layoutWeight(1)
        .height('100%')
      Divider().vertical(true).height('100%')
      Column() { this.SplitPreviewPage() }
        .layoutWeight(1)
        .height('100%')
    }
    .height('100%')
    .width('100%')
  }

  @Builder
  private WorkspacePage() {
    Column() {
      HdsTabs({ barPosition: BarPosition.End, index: this.selectedTab }) {
        TabContent() { this.EditPage() }
          .tabBar(BottomTabBarStyle.of(this.tabSymbol($r('sys.symbol.square_and_pencil')), '编辑'))
        TabContent() { this.PreviewPage() }
          .tabBar(BottomTabBarStyle.of(this.tabSymbol($r('sys.symbol.eye')), '预览'))
        TabContent() { this.OutlinePage() }
          .tabBar(BottomTabBarStyle.of(this.tabSymbol($r('sys.symbol.list_bullet')), '大纲'))
        if (this.wide) {
          TabContent() { this.SplitPage() }
            .tabBar(BottomTabBarStyle.of(this.tabSymbol($r('sys.symbol.rectangle_split_2x1')), '分栏'))
        }
      }
      .onChange((index: number) => { this.selectedTab = index; this.schedulePreview(); })
      .barMode(BarMode.Fixed)
      // barOverlap keeps the bar above the content, so swapping it out for the format bar
      // does not move the text, and the system material gives the translucent look.
      .barOverlap(true)
      .barFloatingStyle(this.floatingBar())
      // While typing, the format bar takes the place of the tab bar. Only one bar is ever
      // visible, which is what keeps the bottom of the screen from carrying two rows.
      .barHeight(this.formatBarActive() ? 0 : 56)
      .layoutWeight(1)
      .width('100%')

      // The bar is always built and only toggles visibility: an if branch inside a @Builder
      // does not rebuild when the state changes, while a property update does.
      this.FormatBar()
    }
    .width('100%')
    .height('100%')
  }

  private formatBarActive(): boolean {
    return this.formatBarShown && this.formatBarWanted();
  }

  /** The format bar only applies to the editable tab of a format that has insert actions. */
  private formatBarWanted(): boolean {
    if (this.currentFormat().inserts.length === 0) return false;
    return this.selectedTab === 0;
  }

  /** The four most common inserts stay on the bar; the rest move into the more menu. */
  private barInserts(): InsertAction[] {
    return this.currentFormat().inserts.slice(0, 4);
  }

  private moreInserts(): MenuElement[] {
    const rest = this.currentFormat().inserts.slice(4);
    const items: MenuElement[] = [];
    for (let index = 0; index < rest.length; index++) {
      const action = rest[index];
      items.push({
        value: action.label,
        symbolIcon: new SymbolGlyphModifier(action.symbol),
        action: (): void => this.insertToken(action)
      });
    }
    return items;
  }

  /**
   * @LocalBuilder, not @Builder: a plain nested @Builder does not keep the state parent-child
   * relationship, so its attributes stop following @State changes. The official guide on
   * @LocalBuilder describes exactly this case.
   */
  @LocalBuilder
  private FormatBar() {
    Row() {
      ForEach(this.barInserts(), (action: InsertAction) => {
        Column() {
          SymbolGlyph(action.symbol)
            .fontSize($r('sys.float.ohos_id_text_size_headline7'))
            .fontColor([$r('sys.color.font_primary')])
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .accessibilityText(action.label)
        .onClick(() => this.insertToken(action))
      }, (action: InsertAction) => action.token)

      if (this.currentFormat().inserts.length > 4) {
        Column() {
          SymbolGlyph($r('sys.symbol.more'))
            .fontSize($r('sys.float.ohos_id_text_size_headline7'))
            .fontColor([$r('sys.color.font_primary')])
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .accessibilityText('更多格式')
        .bindMenu(this.moreInserts())
      }
    }
    .width('100%')
    .height(56)
    .id('marknote-format-bar')
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .visibility(this.formatBarActive() ? Visibility.Visible : Visibility.None)
  }

  /**
   * 底部页签用 HDS 的沉浸光感材质，跟随系统算力自适应，与系统「备忘录」的悬浮半透明页签一致。
   */
  private floatingBar(): HdsTabsFloatingStyle {
    const material: SystemMaterialParams = {
      materialType: hdsMaterial.MaterialType.ADAPTIVE,
      materialLevel: this.materialLevel
    };
    const style: HdsTabsFloatingStyle = {
      barBottomMargin: 28,
      systemMaterialEffect: material
    };
    return style;
  }

  @Builder
  Destination(name: string, _pageInfos: Object) {
    if (name === 'document') {
      HdsNavDestination() {
        this.WorkspacePage()
      }
      .titleBar(this.documentTitle())
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .onBackPressed(() => {
        if (this.routes.size() > 0) this.leaveDocument();
        return true;
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
