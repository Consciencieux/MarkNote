import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import { DocumentInfo, Heading, RecentDocument, RecoveryData, documentOutline, linesIn } from '../model/Document';
import { DocumentFiles, FileContents } from '../storage/DocumentFiles';
import { LocalState } from '../storage/LocalState';

const QUICK_INSERTS: string[] = ['# ', '**', '*', '`', '[]()', '- ', '- [ ] ', '$', '```'];

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

  private showMoreMenu(): void {
    ActionSheet.show({
      title: '更多操作',
      message: '文稿与应用设置',
      sheets: [
        { title: '新建 Markdown', action: () => this.guardChanges(() => this.startNew('markdown')) },
        { title: '新建 SVG', action: () => this.guardChanges(() => this.startNew('svg')) },
        { title: '新建 LaTeX 公式', action: () => this.guardChanges(() => this.startNew('latex')) },
        { title: '打开文件', action: () => this.guardChanges(() => { void this.pickOpen(); }) },
        { title: '另存为', action: () => { void this.saveFile(true); } },
        { title: '外观', action: () => this.showThemeMenu() },
        { title: '开源许可证与隐私说明', action: () => this.openLegal() },
        { title: '返回文稿列表', action: () => this.closeToLibrary() }
      ]
    });
  }

  private navigationMenus(): NavigationMenuItem[] {
    if (this.showLegal) return [{ value: '返回', action: () => { this.showLegal = false; } }];
    if (this.editing) {
      return [
        { value: '保存', action: () => { void this.saveFile(false); } },
        { value: '查找', action: () => { this.searchVisible = true; this.selectedTab = 0; } },
        { value: '更多', action: () => this.showMoreMenu() }
      ];
    }
    return [
      { value: '新建', action: () => this.showNewMenu() },
      { value: '打开', action: () => this.guardChanges(() => { void this.pickOpen(); }) },
      { value: '更多', action: () => this.showHomeMenu() }
    ];
  }

  private showNewMenu(): void {
    ActionSheet.show({
      title: '新建文稿',
      message: '选择要创建的文稿类型',
      sheets: [
        { title: 'Markdown 文稿', action: () => this.guardChanges(() => this.startNew('markdown')) },
        { title: 'SVG 图形', action: () => this.guardChanges(() => this.startNew('svg')) },
        { title: 'LaTeX 数学公式', action: () => this.guardChanges(() => this.startNew('latex')) }
      ]
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

  private sendPreview(controller: webview.WebviewController): void {
    const filename = this.title.toLowerCase();
    let kind: string = 'markdown';
    if (filename.endsWith('.svg')) kind = 'svg';
    if (filename.endsWith('.tex')) kind = 'latex';
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

  private guardChanges(action: () => void): void {
    if (!this.editing && this.recoveryAvailable) {
      AlertDialog.show({
        title: '还有未恢复的草稿',
        message: '新建或打开其他文件会丢弃这份草稿。可以先恢复草稿并保存。',
        primaryButton: { value: '取消', action: () => {} },
        secondaryButton: { value: '放弃草稿继续', action: () => {
          // Keep the draft until the next document actually opens or is created.
          action();
        } }
      });
      return;
    }
    if (!this.editing || !this.isDirty()) {
      action();
      return;
    }
    AlertDialog.show({
      title: '未保存的修改',
      message: '当前文稿有未保存的修改。可以先取消并保存，再继续操作。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '放弃并继续',
        action: () => {
          // Picker cancellation/read failure must retain the current recovery.
          action();
        }
      }
    });
  }

  private startNew(kind: string = 'markdown'): void {
    this.clearRecovery();
    this.info = new DocumentInfo();
    this.info.name = kind === 'svg' ? '未命名.svg' : kind === 'latex' ? '未命名.tex' : '未命名.md';
    this.title = this.info.name;
    this.source = kind === 'svg' ? '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 160">\n  <circle cx="160" cy="80" r="52" fill="#628ac7"/>\n</svg>' :
      kind === 'latex' ? '\\frac{a}{b} + \\sqrt{x^2 + y^2}' : '';
    this.savedText = '';
    this.headings = [];
    this.schedulePreview();
    this.selectedTab = 0;
    this.searchVisible = false;
    this.currentMatch = -1;
    this.selectionStart = 0;
    this.selectionEnd = 0;
    this.editing = true;
  }

  private openDocument(opened: FileContents): void {
    this.info = opened.info;
    this.title = opened.info.name;
    this.source = opened.text;
    this.savedText = opened.text;
    this.headings = this.title.toLowerCase().endsWith('.md') || this.title.toLowerCase().endsWith('.markdown') ? documentOutline(opened.text) : [];
    this.currentMatch = -1;
    this.selectionStart = 0;
    this.selectionEnd = 0;
    this.selectedTab = 0;
    this.searchVisible = false;
    this.editing = true;
    this.clearRecovery();
    this.schedulePreview();
    if (this.context && this.info.uri) {
      void LocalState.addRecent(this.context, this.info.uri, this.info.name).then((items: RecentDocument[]) => {
        this.recents = items;
      }).catch(() => this.toast('最近文稿列表未能更新'));
    }
  }

  private async pickOpen(): Promise<void> {
    if (!this.context) return;
    try {
      const uri = await DocumentFiles.chooseOpen(this.context);
      if (uri.length === 0) return;
      const loaded = DocumentFiles.read(uri);
      this.openDocument(loaded);
    } catch (error) {
      this.toast('打开失败：' + String(error));
    }
  }

  private openRecent(item: RecentDocument): void {
    this.guardChanges(() => {
      try {
        this.openDocument(DocumentFiles.read(item.uri));
      } catch {
        this.toast('原文件授权可能已经失效，请使用“打开”重新选取');
      }
    });
  }

  private async saveFile(asNewFile: boolean): Promise<void> {
    if (!this.context || !this.editing || this.saving) return;
    const snapshot = this.source;
    const oldUri = this.info.uri;
    const oldTitle = this.title;
    const oldSaved = this.savedText;
    let uri = asNewFile ? '' : this.info.uri;
    this.saving = true;
    try {
      if (!uri) {
        uri = await DocumentFiles.chooseSave(this.context, this.title);
        if (!uri) return;
      }
      const target = new DocumentInfo();
      target.uri = uri;
      target.name = this.title;
      target.newline = this.info.newline;
      target.hasBom = this.info.hasBom;
      // A Save picker creates the destination. Existing documents must remain unchanged
      // since the last successful read/save, otherwise overwriting is refused.
      DocumentFiles.write(target, snapshot, !asNewFile && oldUri.length > 0 ? oldSaved : null);
      this.info = target;
      this.savedText = snapshot;
      // Pickers can rename the target; keep the name the user has already chosen
      // when provided, and update metadata from the resulting file if available.
      if (uri !== oldUri || asNewFile) {
        const reopened = DocumentFiles.read(uri);
        this.info.name = reopened.info.name || oldTitle;
        this.title = this.info.name;
      }
      this.toast(this.source === snapshot ? '已保存' : '已保存操作开始时的版本，仍有未保存修改');
      if (!this.isDirty()) this.clearRecovery();
      else this.scheduleRecovery();
      this.recents = await LocalState.addRecent(this.context, uri, this.title);
    } catch (error) {
      this.scheduleRecovery();
      this.toast('保存失败：' + String(error));
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
    draft.hasBom = this.info.hasBom;
    try {
      LocalState.writeDraft(this.context, draft);
      this.recovery = draft;
      this.recoveryAvailable = true;
    } catch {
      this.toast('草稿恢复副本写入失败，请尽快保存文件');
    }
  }

  private restoreRecovery(): void {
    if (!this.recovery) return;
    const draft = this.recovery;
    this.info = new DocumentInfo();
    this.info.name = draft.name;
    this.info.uri = draft.uri;
    this.info.newline = draft.newline;
    this.info.hasBom = draft.hasBom;
    this.title = draft.name;
    this.source = draft.text;
    this.savedText = draft.savedText;
    this.headings = this.title.toLowerCase().endsWith('.md') || this.title.toLowerCase().endsWith('.markdown') ? documentOutline(draft.text) : [];
    this.currentMatch = -1;
    this.selectionStart = 0;
    this.selectionEnd = 0;
    this.editing = true;
    this.selectedTab = 0;
    this.schedulePreview();
  }

  private closeToLibrary(): void {
    this.flushRecovery();
    this.editing = false;
  }

  private updateSource(text: string): void {
    this.source = text;
    this.currentMatch = -1;
    this.headings = this.title.toLowerCase().endsWith('.md') || this.title.toLowerCase().endsWith('.markdown') ? documentOutline(text) : [];
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
              .onClick(() => this.guardChanges(() => { void this.pickOpen(); }))
          }
          .width('100%')
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
              .onClick(() => this.restoreRecovery())
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
        ForEach(QUICK_INSERTS, (token: string) => {
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
      this.QuickKeys()
      Row({ space: 12 }) {
        Text(`${linesIn(this.source)} 行 · ${this.source.length} 字符`)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
        Blank()
        if (this.saving) {
          Text('正在保存…').fontSize(12)
        } else if (this.isDirty() || !this.info.uri) {
          Text('未保存').fontSize(12)
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

  private adjustLayout(width: number): void {
    const next = width >= 720;
    if (this.wide !== next) {
      this.wide = next;
      if (!next && this.selectedTab === 3) this.selectedTab = 0;
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
      TabContent() {
        this.OutlinePage()
      }.tabBar('大纲')
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
