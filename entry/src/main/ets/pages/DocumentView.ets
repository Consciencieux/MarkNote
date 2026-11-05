import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { AdvancedDialogV2Button, ComposeListItem, CustomContentDialogV2, SymbolGlyphModifier } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import {
  HdsNavDestination, HdsNavDestinationTitleMode, hdsMaterial, HdsNavigationTitle,
  HdsNavigationIconOptions, HdsNavigationMenuItemOptions, HdsNavigationMenuContentOptions,
  TitleBarContentOptions, HdsNavigationTitleBarOptions, SystemMaterialParams,
  HdsTabs, HdsTabsFloatingStyle
} from '@kit.UIDesignKit';
import { DocumentInfo, Heading, RecoveryData, linesIn } from '../model/Document';
import { DocumentService } from '../document/DocumentService';
import { DocumentFormat, InsertAction } from '../document/FormatRegistry';
import { SearchHit, TextSearch } from '../document/TextSearch';
import { EditHistory, EditStep } from '../document/EditHistory';
import { FormatBarView } from './FormatBarView';
import { menuBridge } from './DocumentMenus';
import { documentBridge } from './DocumentBridge';
import { LocalState } from '../storage/LocalState';

/**
 * Tab positions on the document page. Preview comes first so a document opens in reading
 * view, the same way Word, Keynote and the system notes app open a file. Named constants
 * keep the index arithmetic readable now that editing is not the first tab.
 */
const TAB_PREVIEW: number = 0;
const TAB_EDIT: number = 1;
const TAB_OUTLINE: number = 2;
const TAB_SPLIT: number = 3;

/**
 * 文稿页：预览、编辑、大纲和分栏，以及它们的标题栏、格式栏和保存/草稿逻辑。
 * 文稿会话由 DocumentService 持有，这里只镜像一份给 UI；首页通过 revision 通知换篇，
 * 通过两种桥（menuBridge、documentBridge）发起菜单动作和「能否离开」的询问。
 */
@Component
export struct DocumentView {
  // 由首页传入。
  @Prop @Watch('onThemeChange') theme: string = 'system';
  @Prop @Watch('onWideChange') wide: boolean = false;
  /** 每打开一篇就加一，用来在路由已经存在时重新载入会话。 */
  @Prop @Watch('loadSession') revision: number = 0;
  onLeave: () => void = (): void => {};
  /** 保存成功后把文件记进最近文稿，列表由首页持有。 */
  onSaved: (uri: string, name: string) => void = (_uri: string, _name: string): void => {};

  private preview: webview.WebviewController = new webview.WebviewController();
  private splitPreview: webview.WebviewController = new webview.WebviewController();
  private previewReady: boolean = false;
  private splitReady: boolean = false;
  private previewTimer: number = -1;
  @State private title: string = '未命名.md';
  @State private source: string = '';
  @State private savedText: string = '';
  @State private selectedTab: number = TAB_PREVIEW;
  /** Format id of the open document, kept as state so the format bar rebuilds on switch. */
  @State private formatId: string = '';
  @State private headings: Heading[] = [];
  @State private saving: boolean = false;
  @State private searchVisible: boolean = false;
  @State private query: string = '';
  @State private replacement: string = '';
  @State private currentMatch: number = -1;
  /** Drives the enabled state of the title bar undo and redo icons. */
  @State private undoAvailable: boolean = false;
  @State private redoAvailable: boolean = false;
  private history: EditHistory = new EditHistory();
  private context: common.UIAbilityContext | null = null;
  private info: DocumentInfo = new DocumentInfo();
  private cursor: TextAreaController = new TextAreaController();
  private selectionStart: number = 0;
  private selectionEnd: number = 0;
  private recoveryTimer: number = -1;
  private materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.EXQUISITE;
  /** 未保存确认弹窗的正文与保存按钮文案，弹窗构建时读取，不需要观察。 */
  private leaveMessage: string = '';
  private leaveSaveLabel: string = '保存';

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.pickMaterialLevel();
    // 文稿页自己的菜单项：另存为和查找只对当前文稿有意义。
    menuBridge.saveAs = (): void => {
      menuBridge.dismiss((): void => { void this.saveFile(true); });
    };
    menuBridge.find = (): void => {
      menuBridge.dismiss((): void => {
        this.searchVisible = true;
        this.selectedTab = TAB_EDIT;
      });
    };
    // 首页在换篇、返回列表前都要先问这里能否离开。
    documentBridge.saveBeforeLeaving = (): Promise<boolean> => this.saveBeforeLeaving();
    documentBridge.requestLeave = (): void => this.requestLeave();
    this.loadSession();
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

  /** 窄屏收起分栏时回到预览，和之前媒体查询监听里的行为一致。 */
  private onWideChange(): void {
    if (!this.wide && this.selectedTab === this.splitTab()) this.selectedTab = TAB_PREVIEW;
  }

  private onThemeChange(): void {
    this.schedulePreview();
  }

  /** 载入当前会话。首次进入和首页换篇（revision 变）都走这里。 */
  private loadSession(): void {
    this.syncFromService();
    // The history belongs to one document. Keeping it across a switch would let undo write
    // the previous document's text into this one.
    this.history.reset(this.source, 0);
    this.refreshHistoryState();
    this.currentMatch = -1;
    this.selectionStart = 0;
    this.selectionEnd = 0;
    this.selectedTab = TAB_PREVIEW;
    // 新文档从预览开始，编辑区不应带着上一篇的光标或编辑态。
    this.stopEditing();
    this.searchVisible = false;
    // 干净文稿会顺手清掉残留草稿；崩溃恢复来的文稿仍是脏的，继续留在磁盘上。
    this.flushRecovery();
  }

  aboutToDisappear(): void {
    this.flushRecovery();
    if (this.recoveryTimer >= 0) clearTimeout(this.recoveryTimer);
    if (this.previewTimer >= 0) clearTimeout(this.previewTimer);
    menuBridge.saveAs = (): void => {};
    menuBridge.find = (): void => {};
    documentBridge.saveBeforeLeaving = (): Promise<boolean> => Promise.resolve(true);
    documentBridge.requestLeave = (): void => {};
  }

  /** 先处理未保存的改动，再关闭会话并请首页弹栈；取消时留在原处。 */
  private requestLeave(): void {
    void this.closeToLibrary().then((left: boolean) => {
      if (left) this.onLeave();
    });
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  private menuIcon(label: string, symbol: Resource, id: string, action: () => void,
    enabled: boolean = true): HdsNavigationMenuItemOptions {
    const content: HdsNavigationIconOptions = {
      label: label,
      icon: symbol,
      isEnabled: enabled,
      action: action,
      componentId: id
    };
    const item: HdsNavigationMenuItemOptions = { content: content };
    return item;
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
      content: content
    };
    return options;
  }

  private openDocumentMenu(): void {
    menuBridge.openDocumentMenu();
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
    // 编辑态只在会话里有一份，页面不再另存一份副本。
    if (!DocumentService.current().editing || !this.isDirty()) return true;
    const canWriteInPlace = this.info.uri.length > 0 && this.info.writable;
    if (canWriteInPlace && await this.saveFile(false)) return true;
    return await this.askSaveOrDiscard();
  }

  /**
   * 未保存的退出确认。true 表示可以离开。
   *
   * 用 DialogV2 的自定义内容弹出框（API 参考：`CustomContentDialogV2`，最多 4 个按钮），
   * 因为只有它的按钮支持 `role`：API 参考 `AdvancedDialogV2Button.role` 的默认值说明是
   * 「根据设置枚举值的不同，系统自动调整按钮的背景色和文字颜色」，`ButtonRole.ERROR` 的
   * 文档说明是「警示按钮，通常用于删除、清空等危险或警示性操作」——「放弃修改」正是这一类。
   * 不用 `AlertDialog`：它的 `fontColor` 只能填色值，没有危险操作的语义位，红色得自己写。
   * 也不用 `AlertDialogV2`：它只接受两个按钮，而这里需要保存、放弃修改、取消三个。
   * 其余按钮不配样式，让系统按各自的默认值给出颜色。
   */
  private askSaveOrDiscard(): Promise<boolean> {
    // The reason matters: an unnamed document needs a name, a read-only one needs another
    // location, and a failed write may be an external modification.
    let message = '这份文稿没能写回原文件。可以先另存为，也可以放弃修改。';
    this.leaveSaveLabel = '另存为';
    if (this.info.uri.length === 0) {
      message = '这份文稿还没有保存到文件。可以先保存，也可以放弃修改。';
      this.leaveSaveLabel = '保存';
    } else if (!this.info.writable) {
      message = '这个文件没有写入权限。可以另存为新文件，也可以放弃修改。';
    }
    this.leaveMessage = message;
    return new Promise<boolean>((resolve: (leave: boolean) => void) => {
      this.getUIContext().getPromptAction().openCustomDialog({
        autoCancel: true,
        // 点遮罩或按 back 关闭弹窗也按取消处理，留在当前文稿。
        // Promise 只认第一次结果，正常点按钮时这里不会覆盖。
        onDidDisappear: (): void => resolve(false),
        builder: (): void => {
          this.LeaveConfirmDialog(resolve);
        }
      }).catch(() => resolve(false));
    });
  }

  @Builder
  private LeaveConfirmDialog(resolve: (leave: boolean) => void) {
    CustomContentDialogV2({
      primaryTitle: '未保存的修改',
      contentBuilder: (): void => {
        this.LeaveConfirmContent();
      },
      buttons: [
        new AdvancedDialogV2Button({
          content: this.leaveSaveLabel,
          action: (): void => {
            this.saveFile(this.info.uri.length > 0 && !this.info.writable)
              .then((saved: boolean) => resolve(saved))
              .catch(() => resolve(false));
          }
        }),
        new AdvancedDialogV2Button({
          content: '放弃修改',
          role: ButtonRole.ERROR,
          action: (): void => resolve(true)
        }),
        new AdvancedDialogV2Button({
          content: '取消',
          action: (): void => resolve(false)
        })
      ]
    })
  }

  /** 内容区只有一句说明，用普通 Text，不额外配字号和颜色。 */
  @Builder
  private LeaveConfirmContent() {
    Text(this.leaveMessage)
      .width('100%')
  }

  private syncFromService(): void {
    const session = DocumentService.current();
    this.info = session.info;
    this.title = session.info.name;
    this.formatId = session.info.formatId;
    this.source = session.source;
    this.savedText = session.savedText;
    this.headings = DocumentService.headingsFor(this.info, this.source);
    this.schedulePreview();
  }

  private async saveFile(asNewFile: boolean): Promise<boolean> {
    if (!this.context || this.saving) return false;
    this.saving = true;
    try {
      const result = await DocumentService.save(this.context, asNewFile);
      this.syncFromService();
      if (!result.saved) return false;
      this.toast(result.message);
      if (!this.isDirty()) this.clearRecovery();
      else this.scheduleRecovery();
      // 最近文稿列表在首页，保存成功只通知过去。
      this.onSaved(this.info.uri, this.title);
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
    if (!this.context || !DocumentService.current().editing) return;
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
    // close() 同时把会话的编辑态置为 false，页面不再维护第二份。
    DocumentService.close();
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
    this.selectedTab = TAB_EDIT;
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
    this.selectedTab = TAB_EDIT;
    setTimeout(() => this.cursor.caretPosition(heading.offset), 20);
  }

  private statusLine(): string {
    const count = `${linesIn(this.source)} 行 · ${this.source.length} 字符`;
    if (this.saving) return `${count} · 正在保存…`;
    if (this.isDirty() || this.info.uri.length === 0) return `${count} · 未保存`;
    if (!this.info.writable) return `${count} · 只读`;
    return `${count} · 已保存`;
  }

  /**
   * 查找栏用官方 Search 的 searchButton 承载「下一处」，onSubmit 与按钮点击共用同一入口，
   * 不再在 Search 旁边另放一个文字按钮。关闭用系统符号的文本按钮。
   * 行内间距和上下留白取系统间距资源（`Row` 的 `space` 只接受数字，所以间距写成子项 margin）。
   */
  @Builder
  private FindBar() {
    Column() {
      Row() {
        Search({ value: this.query, placeholder: '查找文稿内容' })
          .searchButton('下一处')
          .onSubmit(() => this.findNext())
          .onChange((value: string) => { this.query = value; this.currentMatch = -1; })
          .layoutWeight(1)
          .margin({ right: $r('sys.float.padding_level4') })
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
      Row() {
        TextInput({ text: this.replacement, placeholder: '替换为' })
          .onChange((value: string) => { this.replacement = value; })
          .layoutWeight(1)
          .margin({ right: $r('sys.float.padding_level4') })
        Button('替换')
          .onClick(() => this.replaceMatch())
      }
      .width('100%')
      .margin({ top: $r('sys.float.padding_level4') })
    }
    .padding({
      left: $r('sys.float.margin_left'),
      right: $r('sys.float.margin_right'),
      top: $r('sys.float.padding_level4'),
      bottom: $r('sys.float.padding_level4')
    })
    .width('100%')
  }

  @Builder
  private EditPage() {
    Column() {
      // 格式栏常驻在标题栏下方，不跟键盘移动。实心一行，和「备忘录」的编辑区一致。
      FormatBarView({
        visible: this.formatBarWanted(),
        formatId: this.formatId,
        onInsert: (action: InsertAction): void => this.insertToken(action)
      })
      if (this.searchVisible) {
        this.FindBar()
      }
      TextArea({ text: this.source, placeholder: '在这里开始写作…', controller: this.cursor })
        .fontSize($r('sys.float.ohos_id_text_size_body1'))
        .width('100%')
        .layoutWeight(1)
        // TextArea 默认带一层灰底和圆角。编辑区应该就是页面本身，所以底色取透明（不做新颜色），
        // 圆角归零，正文直接落在页面底色上，和预览页是同一张纸。
        .backgroundColor(Color.Transparent)
        // 圆角归零用系统的“无圆角”资源，不写 0。
        .borderRadius($r('sys.float.corner_radius_none'))
        // 切回编辑页签时 Tabs 会把焦点还给上次编辑的 TextArea，光标停在原处并直接拉起键盘，
        // 手感被打断。enableKeyboardOnFocus(false) 让点击以外的获焦不弹键盘，只有点击文字才弹。
        // 这是官方「管理软键盘」和 faqs-arkui-932 推荐的写法。
        .enableKeyboardOnFocus(false)
        .onChange((value: string) => this.updateSource(value))
        .onTextSelectionChange((start: number, end: number) => {
          this.selectionStart = start;
          this.selectionEnd = end;
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_background'))
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
      // 兜底底色跟随页面底色（同一个系统 token），不写死黑白两色；
      // 预览正文的底色由 renderer 的样式表按主题决定。
      .backgroundColor($r('sys.color.ohos_id_color_background'))
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

  /**
   * 大纲是只读的扁平标题列表，层级只用于缩进，没有折叠和重命名。
   * 官方的 TreeView 面向带目录图标、增删改入口的文件树，套在这里会多出用不到的操作，
   * 因此沿用 List 承载行，行内容交给官方 ComposeListItem：主标题是标题文字，
   * 副标题是行号，行高、内边距和字号都由组件按系统规范给出。
   * 层级缩进没有对应的系统 token，是这一处唯一的兜底值。
   */
  @Builder
  private OutlinePage() {
    if (this.headings.length === 0) {
      Column() {
        Text('暂无大纲').fontSize($r('sys.float.ohos_id_text_size_body1'))
        Text('在编辑页使用 #、## 等 Markdown 标题语法即可生成大纲。')
          .fontColor($r('sys.color.font_secondary'))
          .margin({ top: $r('sys.float.padding_level4') })
      }
      // TabContent 默认把不撑满的子组件居中，这里撑满后文字才会从顶部开始排。
      // 留白取系统 margin 资源，不写死数值。
      .padding({
        left: $r('sys.float.margin_left'),
        right: $r('sys.float.margin_right'),
        top: $r('sys.float.padding_level8')
      })
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .height('100%')
    } else {
      List() {
        ForEach(this.headings, (heading: Heading) => {
          ListItem() {
            ComposeListItem({
              contentItem: {
                primaryText: heading.text,
                secondaryText: `第 ${heading.line} 行`
              }
            })
          }
          // 缩进表示 Markdown 标题层级，取系统间距资源（见 outlineIndent）。
          .margin({ left: this.outlineIndent(heading.level) })
          .onClick(() => this.focusHeading(heading))
        }, (heading: Heading) => heading.offset.toString())
      }
      .width('100%')
      .height('100%')
    }
  }

  /**
   * 大纲行的左缩进：按标题层级取系统间距资源，一级到四级分别是
   * 0 / 16 / 32 / 48vp（`padding_level0` / `8` / `16` / `24`），
   * 比四级更深的层级沿用最大那一档，不再补自定义数值。
   */
  private outlineIndent(level: number): Resource {
    const steps: Resource[] = [
      $r('sys.float.padding_level0'),
      $r('sys.float.padding_level8'),
      $r('sys.float.padding_level16'),
      $r('sys.float.padding_level24')
    ];
    const index: number = Math.min(Math.max(level - 1, 0), steps.length - 1);
    return steps[index];
  }

  private splitTab(): number {
    return this.currentFormat().outline ? TAB_SPLIT : TAB_OUTLINE;
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

  /**
   * @LocalBuilder, not @Builder: this subtree contains an if branch for the outline tab,
   * and a plain nested @Builder does not keep the state parent-child relationship, so that
   * branch would not rebuild when the state changes.
   *
   * 内容在标题栏下方截断，页签栏固定在底部，两者都不随键盘移动，所以这里只是一列普通布局。
   */
  @LocalBuilder
  private WorkspacePage() {
    HdsTabs({ barPosition: BarPosition.End, index: this.selectedTab }) {
      // Preview first: opening a document lands in reading view, like the system apps.
      TabContent() { this.PreviewPage() }
        .tabBar(BottomTabBarStyle.of(this.tabSymbol($r('sys.symbol.eye')), '预览'))
      TabContent() { this.EditPage() }
        .tabBar(BottomTabBarStyle.of(this.tabSymbol($r('sys.symbol.square_and_pencil')), '编辑'))
      // Only formats that declare an outline get the tab; plain text and SVG have none.
      if (this.currentFormat().outline) {
        TabContent() { this.OutlinePage() }
          .tabBar(BottomTabBarStyle.of(this.tabSymbol($r('sys.symbol.list_bullet')), '大纲'))
      }
      if (this.wide) {
        TabContent() { this.SplitPage() }
          .tabBar(BottomTabBarStyle.of(this.tabSymbol($r('sys.symbol.rectangle_split_2x1')), '分栏'))
      }
    }
    .onChange((index: number) => {
      this.selectedTab = index;
      // 离开编辑页签就退出编辑态：键盘跟着收起，焦点不再挂在隐藏的 TextArea 上，
      // 回来时也不会把光标和键盘一起带回来。
      if (index !== TAB_EDIT && index !== this.splitTab()) this.stopEditing();
      this.schedulePreview();
    })
    .barMode(BarMode.Fixed)
    // barOverlap 让页签栏浮在内容之上，底部页签的沉浸光感才有内容可映。页签栏不再随键盘
    // 收起或换行，底部始终只有这一条，动画连续。
    .barOverlap(true)
    .barFloatingStyle(this.floatingBar())
    .width('100%')
    .height('100%')
  }

  /** 退出编辑态：收起键盘并放开焦点，用于离开编辑页签和关闭文稿。 */
  private stopEditing(): void {
    this.cursor.stopEditing();
  }

  /** The format bar applies to the editable tab, and to the split tab which also edits. */
  private formatBarWanted(): boolean {
    if (this.currentFormat().inserts.length === 0) return false;
    return this.inEditTab();
  }

  /** 编辑页签和分栏页签都能写；格式栏只在能写的页签出现。 */
  private inEditTab(): boolean {
    return this.selectedTab === TAB_EDIT || this.selectedTab === this.splitTab();
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

  build() {
    HdsNavDestination() {
      this.WorkspacePage()
    }
    .titleBar(this.documentTitle())
    .titleMode(HdsNavDestinationTitleMode.MINI)
    // 页面底色挂在目的页根节点上，标题栏不配置样式：COMMON_BLUR 下标题栏背板默认透明
    // （API 参考 HdsNavigationBackgroundStyle.backgroundColor），透出来就是这里的底色，
    // 顶栏和内容同色。内容区在标题栏下方截断（enableComponentSafeArea），
    // 不会有内容滑到标题栏下面，所以也不需要再关模糊或给它单独铺背板。
    .backgroundColor($r('sys.color.ohos_id_color_background'))
    .onBackPressed(() => {
      this.requestLeave();
      return true;
    })
  }
}
