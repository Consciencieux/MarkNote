import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { ComponentContent, SubHeader, SymbolGlyphModifier } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import {
  HdsNavigation, HdsNavDestination, HdsNavigationTitleMode, HdsNavDestinationTitleMode,
  ScrollEffectType, IconStyleMode, hdsMaterial, HdsNavigationTitle, HdsNavigationIconOptions,
  HdsNavigationMenuItemOptions, HdsNavigationMenuContentOptions, TitleBarContentOptions,
  TitleBarStyleOptions, HdsNavigationTitleBarOptions, ScrollEffectOptions, SystemMaterialParams
} from '@kit.UIDesignKit';
import { DocumentInfo, Heading, RecentDocument, RecoveryData, linesIn } from '../model/Document';
import { DocumentService } from '../document/DocumentService';
import { DocumentFormat, FormatRegistry } from '../document/FormatRegistry';
import { LaunchRequests, OpenRequest } from '../document/LaunchRequests';
import { DocumentFiles } from '../storage/DocumentFiles';
import { LocalState } from '../storage/LocalState';

class MenuBridge {
  confirmNew: (id: string) => void = (_id: string): void => {};
  openFile: () => void = (): void => {};
  saveAs: () => void = (): void => {};
  showTheme: () => void = (): void => {};
  showLegal: () => void = (): void => {};
  closeLibrary: () => void = (): void => {};
  colorMode: ThemeColorMode = ThemeColorMode.SYSTEM;
}

const menuBridge: MenuBridge = new MenuBridge();

@Builder
function HomeMoreMenu() {
  WithTheme({ colorMode: menuBridge.colorMode }) {
    Menu() {
      MenuItem({ content: '外观' })
        .contentFontColor($r('sys.color.font_primary'))
        .onChange(() => menuBridge.showTheme())
      MenuItem({ content: '开源许可证与隐私说明' })
        .contentFontColor($r('sys.color.font_primary'))
        .onChange(() => menuBridge.showLegal())
    }
  }
}

@Builder
function DocumentMoreMenu() {
  WithTheme({ colorMode: menuBridge.colorMode }) {
    Menu() {
      MenuItemGroup({ header: '新建' }) {
        ForEach(FormatRegistry.all(), (item: DocumentFormat) => {
          MenuItem({ content: item.moreTitle })
            .contentFontColor($r('sys.color.font_primary'))
            .onChange(() => menuBridge.confirmNew(item.id))
        }, (item: DocumentFormat) => item.id)
      }
      MenuItem({ content: '打开文件' })
        .contentFontColor($r('sys.color.font_primary'))
        .onChange(() => menuBridge.openFile())
      MenuItem({ content: '另存为' })
        .contentFontColor($r('sys.color.font_primary'))
        .onChange(() => menuBridge.saveAs())
      MenuItem({ content: '外观' })
        .contentFontColor($r('sys.color.font_primary'))
        .onChange(() => menuBridge.showTheme())
      MenuItem({ content: '开源许可证与隐私说明' })
        .contentFontColor($r('sys.color.font_primary'))
        .onChange(() => menuBridge.showLegal())
      MenuItem({ content: '返回文稿列表' })
        .contentFontColor($r('sys.color.font_primary'))
        .onChange(() => menuBridge.closeLibrary())
    }
  }
}

@Entry
@Component
struct Index {
  @State private editing: boolean = false;
  @State private themeOpen: boolean = false;
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
  @State private recoveryAvailable: boolean = false;
  @State private theme: string = 'system';
  @State private saving: boolean = false;
  @State private wide: boolean = false;
  @State private searchVisible: boolean = false;
  @State private query: string = '';
  @State private replacement: string = '';
  @State private currentMatch: number = -1;
  private context: common.UIAbilityContext | null = null;
  private info: DocumentInfo = new DocumentInfo();
  private recovery: RecoveryData | null = null;
  private cursor: TextAreaController = new TextAreaController();
  private selectionStart: number = 0;
  private selectionEnd: number = 0;
  private recoveryTimer: number = -1;
  private routes: NavPathStack = new NavPathStack();
  private libraryScroller: Scroller = new Scroller();
  private homeMenu: ComponentContent<Object> | null = null;
  private documentMenu: ComponentContent<Object> | null = null;

  aboutToAppear(): void {
    menuBridge.confirmNew = (id: string): void => {
      this.confirmSwitch(() => this.startNew(id));
    };
    menuBridge.openFile = (): void => {
      this.confirmSwitch(() => this.pickOpen());
    };
    menuBridge.saveAs = (): void => {
      void this.saveFile(true);
    };
    menuBridge.showTheme = (): void => {
      this.afterMenu(() => {
        this.legalOpen = false;
        this.themeOpen = true;
      });
    };
    menuBridge.showLegal = (): void => {
      this.afterMenu(() => this.openLegal());
    };
    menuBridge.closeLibrary = (): void => {
      this.leaveDocument();
    };
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void this.initialize();
  }

  aboutToDisappear(): void {
    LaunchRequests.unbind();
    this.flushRecovery();
    if (this.recoveryTimer >= 0) clearTimeout(this.recoveryTimer);
    if (this.previewTimer >= 0) clearTimeout(this.previewTimer);
  }

  onBackPress(): boolean {
    if (this.themeOpen) {
      this.themeOpen = false;
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
    this.recovery = LocalState.readDraft(this.context);
    this.recoveryAvailable = this.recovery !== null;
    LaunchRequests.bind((request: OpenRequest) => {
      this.confirmSwitch(() => this.openExternal(request));
    });
  }

  private afterMenu(action: () => void): void {
    setTimeout(action, 200);
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  private changeTheme(choice: string, persist: boolean = true): void {
    this.theme = choice;
    if (choice === 'light') {
      menuBridge.colorMode = ThemeColorMode.LIGHT;
    } else if (choice === 'dark') {
      menuBridge.colorMode = ThemeColorMode.DARK;
    } else {
      menuBridge.colorMode = ThemeColorMode.SYSTEM;
    }
    this.homeMenu = null;
    this.documentMenu = null;
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

  private menuIcon(label: string, symbol: Resource, id: string, action: () => void): HdsNavigationMenuItemOptions {
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
      maxCount: 1,
      value: [this.menuIcon('更多', $r('sys.symbol.dot_grid_2x2'), 'marknote-home-more', () => this.openHomeMenu())]
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
      maxCount: 3,
      value: [
        this.menuIcon('保存', $r('sys.symbol.square_and_arrow_down'), 'marknote-save', () => { void this.saveFile(false); }),
        this.menuIcon('查找', $r('sys.symbol.magnifyingglass'), 'marknote-find', () => {
          this.searchVisible = true;
          this.selectedTab = 0;
        }),
        this.menuIcon('更多', $r('sys.symbol.dot_grid_2x2'), 'marknote-doc-more', () => this.openDocumentMenu())
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
    this.homeMenu = new ComponentContent<Object>(this.getUIContext(), wrapBuilder(HomeMoreMenu));
    this.getUIContext().getPromptAction().openMenu(this.homeMenu, { id: 'marknote-home-more' }, {
      showInSubWindow: false
    }).catch(() => {
      // The menu stays closed when its anchor is not on screen.
    });
  }

  private openDocumentMenu(): void {
    this.documentMenu = new ComponentContent<Object>(this.getUIContext(), wrapBuilder(DocumentMoreMenu));
    this.getUIContext().getPromptAction().openMenu(this.documentMenu, { id: 'marknote-doc-more' }, {
      showInSubWindow: false
    }).catch(() => {
      // The menu stays closed when its anchor is not on screen.
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
    this.themeOpen = false;
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

  private sendPreview(controller: webview.WebviewController): void {
    const kind = this.currentFormat().id;
    const command = 'window.MarknotePreview.update(' + JSON.stringify({
      kind: kind,
      source: this.source,
      theme: this.theme
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

  private confirmSwitch(proceed: () => Promise<void>): void {
    if (!this.editing && this.recoveryAvailable) {
      AlertDialog.show({
        title: '还有未恢复的草稿',
        message: '新建或打开其他文件会丢弃这份草稿。可以先恢复草稿并保存。',
        primaryButton: { value: '取消', action: () => {} },
        secondaryButton: { value: '放弃草稿继续', action: () => { void proceed(); } }
      });
      return;
    }
    if (!this.editing || !this.isDirty()) {
      void proceed();
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '未保存的修改',
      message: '可以保存当前文稿后再打开，也可以放弃修改。取消则留在当前文稿。',
      buttons: [
        { text: '保存并打开', color: $r('sys.color.font_primary') },
        { text: '放弃修改并打开', color: $r('sys.color.font_primary') },
        { text: '取消', color: $r('sys.color.font_secondary') }
      ]
    }).then((result) => {
      if (result.index === 0) {
        void this.saveFile(false).then((opened: boolean) => {
          if (opened) void proceed();
        });
      } else if (result.index === 1) {
        void proceed();
      }
    }).catch(() => {
      // Dismissing the dialog keeps the current document and its draft.
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
    this.closeToLibrary();
    if (this.routes.size() > 0) this.routes.pop();
  }

  private presentOpened(): void {
    this.syncFromService();
    this.currentMatch = -1;
    this.selectionStart = 0;
    this.selectionEnd = 0;
    this.selectedTab = 0;
    this.searchVisible = false;
    this.themeOpen = false;
    this.legalOpen = false;
    this.clearRecovery();
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
    this.recovery = null;
    this.recoveryAvailable = false;
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
      this.recovery = draft;
      this.recoveryAvailable = true;
    } catch {
      this.toast('草稿恢复副本写入失败，请尽快保存文件');
    }
  }

  private async restoreRecovery(): Promise<void> {
    if (!this.recovery) return;
    await DocumentService.restore(this.recovery);
    this.syncFromService();
    this.currentMatch = -1;
    this.selectionStart = 0;
    this.selectionEnd = 0;
    this.selectedTab = 0;
    this.searchVisible = false;
    this.showDocumentRoute();
  }

  private closeToLibrary(): void {
    this.flushRecovery();
    DocumentService.close();
    this.editing = false;
    this.themeOpen = false;
  }

  private updateSource(text: string): void {
    DocumentService.edit(text);
    this.source = text;
    this.currentMatch = -1;
    this.headings = DocumentService.headingsFor(this.info, text);
    this.scheduleRecovery();
    this.schedulePreview();
  }

  private findNext(): void {
    if (!this.query) return;
    this.selectedTab = 0;
    const from = this.currentMatch >= 0 ? this.currentMatch + this.query.length : 0;
    let pos = this.source.indexOf(this.query, from);
    if (pos < 0) pos = this.source.indexOf(this.query);
    this.currentMatch = pos;
    if (pos < 0) {
      this.toast('没有找到匹配内容');
    } else {
      setTimeout(() => this.cursor.setTextSelection(pos, pos + this.query.length), 20);
    }
  }

  private replaceMatch(): void {
    if (!this.query) return;
    const start = this.currentMatch;
    if (start < 0 || this.source.slice(start, start + this.query.length) !== this.query) {
      this.findNext();
      return;
    }
    const changed = this.source.slice(0, start) + this.replacement + this.source.slice(start + this.query.length);
    this.updateSource(changed);
    this.currentMatch = -1;
    setTimeout(() => this.cursor.caretPosition(start + this.replacement.length), 20);
  }

  private insertToken(token: string): void {
    const start = Math.min(this.selectionStart, this.selectionEnd);
    const end = Math.max(this.selectionStart, this.selectionEnd);
    const selected = this.source.slice(start, end);
    let prefix = token;
    let suffix = '';
    if (token === '**' || token === '*' || token === '`' || token === '$') suffix = token;
    if (token === '[]()') { prefix = '['; suffix = '](url)'; }
    if (token === '```') { prefix = '```\n'; suffix = '\n```'; }
    this.updateSource(this.source.slice(0, start) + prefix + selected + suffix + this.source.slice(end));
    const position = start + prefix.length + selected.length;
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

  private insertLabel(token: string): string {
    if (token === '# ') return '标题';
    if (token === '**') return '加粗';
    if (token === '*') return '斜体';
    if (token === '`') return '代码';
    if (token === '[]()') return '链接';
    if (token === '- ') return '列表';
    if (token === '- [ ] ') return '待办';
    if (token === '$') return '公式';
    if (token === '```') return '代码块';
    return token;
  }

  private insertSymbol(token: string): Resource {
    if (token === '# ') return $r('sys.symbol.textformat');
    if (token === '**') return $r('sys.symbol.bold');
    if (token === '*') return $r('sys.symbol.italic');
    if (token === '`') return $r('sys.symbol.code');
    if (token === '[]()') return $r('sys.symbol.link');
    if (token === '- ') return $r('sys.symbol.list_bullet');
    if (token === '- [ ] ') return $r('sys.symbol.checkmark_square');
    if (token === '$') return $r('sys.symbol.sum_rectangle_fill');
    if (token === '```') return $r('sys.symbol.code_square');
    return $r('sys.symbol.plus');
  }

  private editorTools(): ToolbarItem[] {
    const tokens = this.currentFormat().inserts;
    const items: ToolbarItem[] = [];
    for (let index = 0; index < tokens.length; index++) {
      const token = tokens[index];
      const icon = new SymbolGlyphModifier(this.insertSymbol(token));
      const item: ToolbarItem = {
        value: this.insertLabel(token),
        symbolIcon: icon,
        action: (): void => this.insertToken(token)
      };
      items.push(item);
    }
    return items;
  }

  private hideEditorTools(): boolean {
    if (this.currentFormat().inserts.length === 0) return true;
    if (this.selectedTab === 0) return false;
    return !(this.wide && this.selectedTab === this.splitTab());
  }

  private recoveryName(): string {
    if (this.recovery === null) return '';
    return this.recovery.name;
  }

  @Builder
  NewDocumentMenu() {
    WithTheme({ colorMode: menuBridge.colorMode }) {
      Menu() {
        ForEach(FormatRegistry.all(), (item: DocumentFormat) => {
          MenuItem({ content: item.sheetTitle })
            .contentFontColor($r('sys.color.font_primary'))
            .onChange(() => this.confirmSwitch(() => this.startNew(item.id)))
        }, (item: DocumentFormat) => item.id)
      }
    }
  }

  @Builder
  RecoveryHeader() {
    SubHeader({ primaryTitle: '未保存的文稿' })
  }

  @Builder
  RecentHeader() {
    SubHeader({ primaryTitle: '最近文稿' })
  }

  @Builder
  DocumentRow(title: string, detail: string, symbol: Resource) {
    Row({ space: 12 }) {
      SymbolGlyph(symbol)
        .fontSize(24)
        .fontColor([$r('sys.color.font_primary')])
      Column({ space: 2 }) {
        Text(title)
          .fontSize($r('sys.float.ohos_id_text_size_body1'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(detail)
          .fontSize($r('sys.float.ohos_id_text_size_body2'))
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
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
    List({ scroller: this.libraryScroller }) {
      ListItem() {
        Column({ space: 12 }) {
          Text('离线编辑，随时保存到自己的文件。')
            .fontSize($r('sys.float.ohos_id_text_size_body1'))
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
          Row({ space: 12 }) {
            Button('新建文稿')
              .bindMenu(this.NewDocumentMenu)
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

      if (this.recoveryAvailable) {
        ListItemGroup({ header: this.RecoveryHeader, style: ListItemGroupStyle.CARD }) {
          ListItem() {
            this.DocumentRow('恢复上次的编辑', this.recoveryName(), $r('sys.symbol.doc_text_badge_clock'))
          }
          .onClick(() => { void this.restoreRecovery(); })
        }
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

  @Builder
  private FindBar() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Search({ value: this.query, placeholder: '查找文稿内容' })
          .onChange((value: string) => { this.query = value; this.currentMatch = -1; })
          .layoutWeight(1)
        Button('下一处').onClick(() => this.findNext())
        Button('关闭')
          .buttonStyle(ButtonStyleMode.NORMAL)
          .onClick(() => this.searchVisible = false)
      }
      Row({ space: 8 }) {
        TextInput({ text: this.replacement, placeholder: '替换为' })
          .onChange((value: string) => { this.replacement = value; })
          .layoutWeight(1)
        Button('替换').onClick(() => this.replaceMatch())
      }
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
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
        .onChange((value: string) => this.updateSource(value))
        .onTextSelectionChange((start: number, end: number) => {
          this.selectionStart = start;
          this.selectionEnd = end;
        })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private PreviewPage() {
    Web({ src: $rawfile('preview/index.html'), controller: this.preview })
      .javaScriptAccess(true)
      .domStorageAccess(false)
      .onPageEnd(() => { this.previewReady = true; this.sendPreview(this.preview); })
      .width('100%')
      .height('100%')
  }

  @Builder
  private SplitPreviewPage() {
    Web({ src: $rawfile('preview/index.html'), controller: this.splitPreview })
      .javaScriptAccess(true)
      .domStorageAccess(false)
      .onPageEnd(() => { this.splitReady = true; this.sendPreview(this.splitPreview); })
      .width('100%')
      .height('100%')
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

  @Builder
  ThemeChoice(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize($r('sys.float.ohos_id_text_size_body1'))
        .layoutWeight(1)
      Radio({ value: value, group: 'marknote-theme' })
        .checked(this.theme === value)
        .onChange((checked: boolean) => {
          if (checked) this.changeTheme(value);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .onClick(() => this.changeTheme(value))
  }

  @Builder
  private ThemePage() {
    Column() {
      this.ThemeChoice('跟随系统', 'system')
      this.ThemeChoice('浅色', 'light')
      this.ThemeChoice('深色', 'dark')
    }
    .width('100%')
    .padding({ top: 8, bottom: 16 })
  }

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
      .divider({ strokeWidth: 1, startMargin: 16, endMargin: 16 })
    }
  }

  private splitTab(): number {
    return this.currentFormat().outline ? 3 : 2;
  }

  private adjustLayout(width: number): void {
    const next = width >= 720;
    if (this.wide !== next) {
      this.wide = next;
      if (!next && this.selectedTab === this.splitTab()) this.selectedTab = 0;
    }
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
    Tabs({ barPosition: BarPosition.End, index: this.selectedTab }) {
      TabContent() { this.EditPage() }.tabBar('编辑')
      TabContent() { this.PreviewPage() }.tabBar('预览')
      if (this.currentFormat().outline) {
        TabContent() { this.OutlinePage() }.tabBar('大纲')
      }
      if (this.wide) {
        TabContent() { this.SplitPage() }.tabBar('分栏')
      }
    }
    .onChange((index: number) => { this.selectedTab = index; this.schedulePreview(); })
    .barMode(BarMode.Fixed)
    .width('100%')
    .height('100%')
    .onAreaChange((_oldValue: Area, value: Area) => {
      const width = parseFloat(value.width.toString());
      if (!isNaN(width)) this.adjustLayout(width);
    })
  }

  @Builder
  Destination(name: string, _pageInfos: Object) {
    if (name === 'document') {
      HdsNavDestination() {
        this.WorkspacePage()
      }
      .titleBar(this.documentTitle())
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .toolbarConfiguration(this.editorTools())
      .hideToolBar(this.hideEditorTools())
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
      .width('100%')
      .height('100%')
    }
    .bindSheet($$this.themeOpen, this.ThemePage(), {
      title: { title: '外观' },
      showClose: true,
      height: 320,
      preferType: SheetType.BOTTOM
    })
    .bindSheet($$this.legalOpen, this.LegalPage(), {
      title: { title: '开源许可证与隐私' },
      showClose: true,
      height: SheetSize.LARGE,
      preferType: SheetType.BOTTOM
    })
    .width('100%')
    .height('100%')
  }
}
