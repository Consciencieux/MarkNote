import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { SymbolGlyphModifier, window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import {
  HdsNavDestination, HdsNavDestinationTitleMode,
  ScrollEffectType, IconStyleMode, hdsMaterial, HdsNavigationTitle, HdsNavigationIconOptions,
  HdsNavigationMenuItemOptions, HdsNavigationMenuContentOptions, TitleBarContentOptions,
  TitleBarStyleOptions, HdsNavigationTitleBarOptions, ScrollEffectOptions, SystemMaterialParams,
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

  @State private editing: boolean = false;
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
  /** 软键盘是否在屏幕上。格式栏和页签栏的切换都跟着它走。 */
  @State private typing: boolean = false;
  /** 键盘顶端到页面底部的距离（vp）。页面不随键盘压缩，所以位置要自己算。 */
  @State private keyboardInset: number = 0;
  private history: EditHistory = new EditHistory();
  private context: common.UIAbilityContext | null = null;
  private mainWindow: window.Window | null = null;
  /** 键盘高度监听是否已生效；生效后格式栏只跟键盘走，不再用焦点兜底。 */
  private keyboardBound: boolean = false;
  /** 绑定监听时的窗口高度（px），用来判断窗口是否已经替我们避让过键盘。 */
  private windowHeightPx: number = 0;
  /** 当前键盘高度（px），0 表示没有键盘。 */
  private keyboardHeightPx: number = 0;
  /** 工作区底边在窗口里的位置（px），由 onAreaChange 实测得到。 */
  private pageBottomPx: number = 0;
  private info: DocumentInfo = new DocumentInfo();
  private cursor: TextAreaController = new TextAreaController();
  private selectionStart: number = 0;
  private selectionEnd: number = 0;
  private recoveryTimer: number = -1;
  private materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.EXQUISITE;

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.bindKeyboard();
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
   * 格式栏的显隐和位置都跟着键盘走，而不是跟着输入框焦点走。
   * 官方 FAQ 把 onFocus/onBlur 列为「间接判断」，而点格式栏里的按钮或展开菜单会让
   * TextArea 失焦，用 onBlur 隐藏会导致栏自己消失。keyboardHeightChange 弹出时高度
   * 非零、收起时为 0，是官方给出的可靠信号。
   *
   * 这块页面本身不随键盘压缩（实测弹键盘前后窗口高度都是 2832px），页签栏和格式栏都会
   * 落在键盘后面，所以位置按官方「键盘上方自定义工具栏」的方案二自己算：用工作区实测的
   * 底边和键盘顶端求差，把栏抬到键盘上方。
   */
  private bindKeyboard(): void {
    if (!this.context) return;
    window.getLastWindow(this.context).then((win: window.Window) => {
      this.mainWindow = win;
      this.keyboardBound = true;
      this.windowHeightPx = win.getWindowProperties().windowRect.height;
      win.on('keyboardHeightChange', (height: number) => {
        this.keyboardHeightPx = height;
        this.typing = height > 0;
        this.applyKeyboardInset();
      });
    }).catch(() => {
      // 监听不到键盘时退回焦点事件，由 TextArea 的 onFocus 兜底显示格式栏。
    });
  }

  /**
   * 键盘贴着屏幕底边，页面底边却停在它上面一段（HDS 导航容器自己留了底部空间），
   * 所以格式栏要抬的距离是「页面底边到键盘顶端」，两边都换算成 px 再减。
   */
  private applyKeyboardInset(): void {
    if (this.keyboardHeightPx <= 0) {
      this.keyboardInset = 0;
      return;
    }
    const keyboardTopPx = this.windowHeightPx - this.keyboardHeightPx;
    const gapPx = Math.max(0, this.pageBottomPx - keyboardTopPx);
    this.keyboardInset = this.getUIContext().px2vp(gapPx);
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
    if (this.mainWindow !== null) {
      this.mainWindow.off('keyboardHeightChange');
      this.mainWindow = null;
    }
    this.keyboardBound = false;
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

  private openDocumentMenu(): void {
    menuBridge.openDocumentMenu();
  }

  private afterMenu(next: () => void): void {
    menuBridge.dismiss(next);
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

  private syncFromService(): void {
    const session = DocumentService.current();
    this.info = session.info;
    this.title = session.info.name;
    this.formatId = session.info.formatId;
    this.source = session.source;
    this.savedText = session.savedText;
    this.editing = session.editing;
    this.headings = DocumentService.headingsFor(this.info, this.source);
    this.schedulePreview();
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
        // 切回编辑页签时 Tabs 会把焦点还给上次编辑的 TextArea，光标停在原处并直接拉起键盘，
        // 手感被打断。enableKeyboardOnFocus(false) 让点击以外的获焦不弹键盘，只有点击文字才弹。
        // 这是官方「管理软键盘」和 faqs-arkui-932 推荐的写法。
        .enableKeyboardOnFocus(false)
        .onFocus(() => {
          if (!this.keyboardBound) this.typing = true;
        })
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
   * @LocalBuilder, not @Builder: this subtree contains an if branch for the outline tab and
   * the format bar, and a plain nested @Builder does not keep the state parent-child
   * relationship, so those branches would not rebuild when the state changes.
   */
  @LocalBuilder
  private WorkspacePage() {
    // Stack + 底部对齐：页面不会随键盘压缩，所以格式栏用 keyboardInset 抬到键盘顶端。
    // 这是官方「键盘上方自定义工具栏」FAQ 的方案二。
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
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
        // barOverlap keeps the bar above the content, so swapping it out for the format bar
        // does not move the text, and the system material gives the translucent look.
        .barOverlap(true)
        .barFloatingStyle(this.floatingBar())
        // 打字时页签栏收起，底部只留格式栏，避免两行栏叠在一起。
        .barHeight(this.tabBarHidden() ? 0 : 56)
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      // 编辑区让开格式栏：栏浮在键盘上方，内容要停在栏的上沿，光标才不会藏在栏后面。
      .padding({ bottom: this.formatBarActive() ? this.keyboardInset + 56 : 0 })

      // The bar is a real component, so its own @Prop drives the rebuild. A nested @Builder
      // would not refresh here: the official @Builder guide requires reference passing at
      // every nesting level for the innermost builder to update.
      FormatBarView({
        visible: this.formatBarActive(),
        formatId: this.formatId,
        onInsert: (action: InsertAction): void => this.insertToken(action)
      })
        .margin({ bottom: this.keyboardInset })
    }
    .width('100%')
    .height('100%')
    // 实测工作区底边：键盘贴屏幕底边，页面底边却在它上面一段，差多少抬多少。
    .onAreaChange((_old: Area, now: Area) => {
      this.pageBottomPx = this.getUIContext().vp2px(Number(now.globalPosition.y) + Number(now.height));
      this.applyKeyboardInset();
    })
  }

  private formatBarActive(): boolean {
    return this.typing && this.formatBarWanted();
  }

  /** 打字时页签栏让位；没有快捷插入的格式也先收起，避免页签栏被键盘挡住。 */
  private tabBarHidden(): boolean {
    return this.typing && this.inEditTab();
  }

  /** 退出编辑态：收起键盘并放开焦点，用于离开编辑页签和关闭文稿。 */
  private stopEditing(): void {
    this.cursor.stopEditing();
    this.typing = false;
    this.keyboardInset = 0;
  }


  /** The format bar applies to the editable tab, and to the split tab which also edits. */
  private formatBarWanted(): boolean {
    if (this.currentFormat().inserts.length === 0) return false;
    return this.inEditTab();
  }

  /** 编辑页签和分栏页签都能写，格式栏和「退出编辑态」的判断都用它。 */
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
    .onBackPressed(() => {
      this.requestLeave();
      return true;
    })
  }
}
