import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import { DocumentInfo, Heading, RecentDocument, RecoveryData, linesIn } from '../model/Document';
import { DocumentService } from '../document/DocumentService';
import { DocumentFormat, FormatRegistry } from '../document/FormatRegistry';
import { LaunchRequests, OpenRequest } from '../document/LaunchRequests';
import { DocumentFiles } from '../storage/DocumentFiles';
import { LocalState } from '../storage/LocalState';

interface ActionChoice {
  title: string;
  action: () => void;
}

@Entry
@Component
struct Index {
  @State private editing: boolean = false;
  @State private showLegal: boolean = false;
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

  aboutToAppear(): void {
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
    if (this.showLegal) {
      this.showLegal = false;
      return true;
    }
    if (this.editing) {
      this.closeToLibrary();
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

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  private changeTheme(choice: string, persist: boolean = true): void {
    this.theme = choice;
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

  private showThemeMenu(): void {
    ActionSheet.show({
      title: '外观',
      message: '应用与文档预览同步设置',
      sheets: [
        { title: '跟随系统', action: () => this.changeTheme('system') },
        { title: '浅色', action: () => this.changeTheme('light') },
        { title: '深色', action: () => this.changeTheme('dark') }
      ]
    });
  }

  private creationChoices(moreMenu: boolean): ActionChoice[] {
    const formats = FormatRegistry.all();
    const choices: ActionChoice[] = [];
    for (let index = 0; index < formats.length; index++) {
      const item = formats[index];
      const id = item.id;
      choices.push({
        title: moreMenu ? item.moreTitle : item.sheetTitle,
        action: () => this.confirmSwitch(() => this.startNew(id))
      });
    }
    return choices;
  }

  private showMoreMenu(): void {
    const sheets = this.creationChoices(true);
    sheets.push({ title: '打开文件', action: () => this.confirmSwitch(() => this.pickOpen()) });
    sheets.push({ title: '另存为', action: () => { void this.saveFile(true); } });
    sheets.push({ title: '外观', action: () => this.showThemeMenu() });
    sheets.push({ title: '开源许可证与隐私说明', action: () => this.openLegal() });
    sheets.push({ title: '返回文稿列表', action: () => this.closeToLibrary() });
    ActionSheet.show({ title: '更多操作', message: '文稿与应用设置', sheets: sheets });
  }

  private menuItem(label: string, symbol: Resource, action: () => void): NavigationMenuItem {
    const icon: SymbolGlyphModifier = new SymbolGlyphModifier(symbol);
    icon.fontColor([$r('sys.color.font_primary')]);
    return { value: label, symbolIcon: icon, action: action };
  }

  private navigationMenus(): NavigationMenuItem[] {
    if (this.showLegal) {
      return [this.menuItem('返回', $r('sys.symbol.chevron_left'), () => { this.showLegal = false; })];
    }
    if (this.editing) {
      return [
        this.menuItem('保存', $r('sys.symbol.square_and_arrow_down'), () => { void this.saveFile(false); }),
        this.menuItem('查找', $r('sys.symbol.magnifyingglass'), () => { this.searchVisible = true; this.selectedTab = 0; }),
        this.menuItem('更多', $r('sys.symbol.more'), () => this.showMoreMenu())
      ];
    }
    return [];
  }

  private showNewMenu(): void {
    ActionSheet.show({
      title: '新建文稿',
      message: '选择要创建的文稿类型',
      sheets: this.creationChoices(false)
    });
  }

  private showHomeMenu(): void {
    ActionSheet.show({
      title: '设置与说明',
      message: '外观与许可说明',
      sheets: [
        { title: '外观', action: () => this.showThemeMenu() },
        { title: '开源许可证与隐私说明', action: () => this.openLegal() }
      ]
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
    this.showLegal = true;
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

  private presentOpened(): void {
    this.syncFromService();
    this.currentMatch = -1;
    this.selectionStart = 0;
    this.selectionEnd = 0;
    this.selectedTab = 0;
    this.searchVisible = false;
    this.clearRecovery();
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
  }

  private closeToLibrary(): void {
    this.flushRecovery();
    DocumentService.close();
    this.editing = false;
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

  @Builder
  private LibraryPage() {
    Scroll() {
      Column({ space: 24 }) {
        Column({ space: 12 }) {
          Text('离线编辑，随时保存到自己的文件。')
            .fontSize(16)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
          Row({ space: 12 }) {
            Button('新建文稿', { type: ButtonType.Capsule })
              .layoutWeight(1)
              .onClick(() => this.showNewMenu())
            Button('打开文件', { type: ButtonType.Capsule })
              .buttonStyle(ButtonStyleMode.NORMAL)
              .layoutWeight(1)
              .onClick(() => this.confirmSwitch(() => this.pickOpen()))
          }
          .width('100%')
          Button('外观与说明', { type: ButtonType.Normal })
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .fontColor($r('sys.color.font_secondary'))
            .onClick(() => this.showHomeMenu())
        }
        .width('100%')

        if (this.recoveryAvailable) {
          Column({ space: 10 }) {
            Text('未保存的文稿')
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .width('100%')
            Button('恢复上次的编辑', { type: ButtonType.Normal })
              .width('100%')
              .onClick(() => { void this.restoreRecovery(); })
          }
          .width('100%')
        }

        Column({ space: 12 }) {
          Text('最近文稿')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .width('100%')
          if (this.recents.length === 0) {
            Text('最近打开的文件会显示在这里')
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
              .padding({ top: 8, bottom: 8 })
          } else {
            ForEach(this.recents, (item: RecentDocument) => {
              Column() {
                Row({ space: 12 }) {
                  Column({ space: 4 }) {
                    Text(item.name)
                      .fontSize(16)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text('点击继续编辑')
                      .fontSize(12)
                      .fontColor($r('sys.color.font_secondary'))
                  }
                  .layoutWeight(1)
                  Text('›').fontColor($r('sys.color.font_secondary'))
                }
                .width('100%')
                .padding({ top: 10, bottom: 10 })
                .onClick(() => this.openRecent(item))
                Divider()
              }
            }, (item: RecentDocument) => item.uri)
          }
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, top: 16, bottom: 40 })
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private FindBar() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Search({ value: this.query, placeholder: '查找文稿内容' })
          .onChange((value: string) => { this.query = value; this.currentMatch = -1; })
          .layoutWeight(1)
        Button('下一处').onClick(() => this.findNext())
        Button('关闭', { type: ButtonType.Normal })
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
  private QuickKeys() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.currentFormat().inserts, (token: string) => {
          Button(token, { type: ButtonType.Normal })
            .buttonStyle(ButtonStyleMode.NORMAL)
            .onClick(() => this.insertToken(token))
        }, (token: string) => token)
      }
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  private EditPage() {
    Column({ space: 0 }) {
      if (this.searchVisible) {
        this.FindBar()
      }
      TextArea({ text: this.source, placeholder: '在这里开始写作…', controller: this.cursor })
        .fontSize(16)
        .fontFamily('monospace')
        .width('100%')
        .layoutWeight(1)
        .onChange((value: string) => this.updateSource(value))
        .onTextSelectionChange((start: number, end: number) => {
          this.selectionStart = start;
          this.selectionEnd = end;
        })
      if (this.currentFormat().inserts.length > 0) {
        this.QuickKeys()
      }
      Row({ space: 12 }) {
        Text(`${linesIn(this.source)} 行 · ${this.source.length} 字符`)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
        Blank()
        if (this.saving) {
          Text('正在保存…').fontSize(12)
        } else if (this.isDirty() || !this.info.uri) {
          Text('未保存').fontSize(12)
        } else if (!this.info.writable) {
          Text('只读').fontSize(12)
        } else {
          Text('已保存').fontSize(12)
        }
      }
      .padding({ left: 16, right: 16, bottom: 8 })
      .width('100%')
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
      Column({ space: 18 }) {
        Text('隐私说明').fontSize(22).fontWeight(FontWeight.Medium)
        Text('文稿在设备本地编辑。应用没有账号、广告、遥测或联网接口，也不上传文稿。文件由系统文件选择器授权，草稿保存在应用私有目录。')
          .fontSize(15)
        Text('第三方开源许可证').fontSize(22).fontWeight(FontWeight.Medium)
        Text(this.legalText).fontSize(12).fontFamily('monospace')
          .width('100%')
          .copyOption(CopyOptions.LocalDevice)
      }
      .alignItems(HorizontalAlign.Start)
      .padding(20)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private OutlinePage() {
    if (this.headings.length === 0) {
      Column({ space: 10 }) {
        Text('暂无大纲').fontSize(18)
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
                .fontSize(16)
                .maxLines(2)
                .layoutWeight(1)
              Text(`第 ${heading.line} 行`)
                .fontSize(12)
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
    Row({ space: 0 }) {
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
      TabContent() {
        this.EditPage()
      }.tabBar('编辑')
      TabContent() {
        this.PreviewPage()
      }.tabBar('预览')
      if (this.currentFormat().outline) {
        TabContent() {
          this.OutlinePage()
        }.tabBar('大纲')
      }
      if (this.wide) {
        TabContent() {
          this.SplitPage()
        }.tabBar('分栏')
      }
    }
    .onChange((index: number) => { this.selectedTab = index; this.schedulePreview(); })
    .barMode(BarMode.Fixed)
    .width('100%')
    .height('100%')
    .onAreaChange((oldValue: Area, value: Area) => {
      const width = parseFloat(value.width.toString());
      if (!isNaN(width)) this.adjustLayout(width);
    })
  }

  build() {
    Navigation() {
      if (this.showLegal) {
        this.LegalPage()
      } else if (this.editing) {
        this.WorkspacePage()
      } else {
        this.LibraryPage()
      }
    }
    .title(this.showLegal ? '开源许可证与隐私' : this.editing ? this.title : '文稿')
    .titleMode(this.showLegal || this.editing ? NavigationTitleMode.Mini : NavigationTitleMode.Full)
    .mode(NavigationMode.Stack)
    .menus(this.navigationMenus())
    .width('100%')
    .height('100%')
  }
}
