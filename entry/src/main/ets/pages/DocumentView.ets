import { common } from '@kit.AbilityKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import {
  HdsNavDestination, HdsNavDestinationTitleMode, HdsNavigationTitle,
  HdsNavigationIconOptions, HdsNavigationMenuItemOptions, HdsNavigationMenuContentOptions,
  TitleBarContentOptions, HdsNavigationTitleBarOptions, HdsTabs, hdsMaterial
} from '@kit.UIDesignKit';
import { DocumentInfo, Heading, RecoveryData } from '../model/Document';
import { DocumentService } from '../document/DocumentService';
import { DocumentFormat, InsertAction } from '../document/FormatRegistry';
import { SearchHit, TextSearch } from '../document/TextSearch';
import { EditHistory, EditStep } from '../document/EditHistory';
import { FormatBarView } from './FormatBarView';
import { DocumentOutlineView } from './DocumentOutlineView';
import { DocumentPreviewView } from './DocumentPreviewView';
import { DocumentScrollLayer } from './DocumentScrollLayer';
import { PageTabContentPolicy, PageTabsPolicy } from './PageScrollPolicy';
import { menuBridge } from './DocumentMenus';
import { documentBridge } from './DocumentBridge';
import { scrollingTitleBar } from './HdsMaterialStyles';
import { LocalState } from '../storage/LocalState';

/**
 * Tab positions on the document page. Preview comes first so a document opens in reading
 * view. Named constants keep the index arithmetic readable now that editing is not the first tab.
 */
const TAB_PREVIEW: number = 0;
const TAB_EDIT: number = 1;
const TAB_OUTLINE: number = 2;
const TAB_SPLIT: number = 3;
/**
 * 文稿页：预览、编辑、大纲和分栏，以及它们的悬浮操作栏和保存/草稿逻辑。
 * 文稿会话由 DocumentService 持有，这里只镜像一份给 UI；首页通过 revision 通知换篇，
 * 通过两种桥（menuBridge、documentBridge）发起菜单动作和「能否离开」的询问。
 */
@Component
export struct DocumentView {
  // 由首页传入。
  @Prop theme: string = 'system';
  @Prop @Watch('onWideChange') wide: boolean = false;
  /** 每打开一篇就加一，用来在路由已经存在时重新载入会话。 */
  @Prop @Watch('loadSession') revision: number = 0;
  onLeave: () => void = (): void => {};
  /** 保存成功后把文件记进最近文稿，列表由首页持有。 */
  onSaved: (uri: string, name: string) => void = (_uri: string, _name: string): void => {};
  /** 这一次载入已经问过是否另存为的 URI，换篇后才再问。 */
  private retainOfferedUri: string = '';

  private tabContentPolicy: PageTabContentPolicy = new PageTabContentPolicy();
  private tabsPolicy: PageTabsPolicy = new PageTabsPolicy();
  private previewScroller: Scroller = new Scroller();
  private editScroller: Scroller = new Scroller();
  private outlineScroller: Scroller = new Scroller();
  private splitEditScroller: Scroller = new Scroller();
  private splitPreviewScroller: Scroller = new Scroller();
  @State private title: string = '未命名.md';
  @State private source: string = '';
  @State private savedText: string = '';
  @State private selectedTab: number = TAB_PREVIEW;
  /** Format id of the open document, kept as state so the format bar rebuilds on switch. */
  @State private formatId: string = '';
  @State private headings: Heading[] = [];
  @State private parseRevision: number = 0;
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
  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
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


  /** 窄屏收起分栏时回到预览，和之前媒体查询监听里的行为一致。 */
  private onWideChange(): void {
    if (!this.wide && this.selectedTab === this.splitTab()) this.selectedTab = TAB_PREVIEW;
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
    this.offerRetainCopy();
  }

  /**
   * 其他应用交来的 URI 往往只有本次授权。能打开但不持久时问一次另存为，
   * 成功后的新 URI 由保存流程记入最近文稿。
   */
  private offerRetainCopy(): void {
    const uri = this.info.uri;
    if (uri.length === 0 || this.info.persistent) {
      this.retainOfferedUri = '';
      return;
    }
    if (this.retainOfferedUri === uri) return;
    this.retainOfferedUri = uri;
    this.askRetainCopy();
  }

  /**
   * 与未保存确认同一套《警告弹窗》排布：HORIZONTAL，左右都是 DEFAULT 蓝字。
   * 侧滑、返回键和点击遮罩等于「暂不」。
   */
  private askRetainCopy(): void {
    this.getUIContext().showAlertDialog({
      message: '此文件的访问权限无法长期保留。是否另存一份，以便以后打开？',
      autoCancel: true,
      buttonDirection: DialogButtonDirection.HORIZONTAL,
      buttons: [
        {
          value: '暂不',
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {}
        },
        {
          value: '另存为',
          style: DialogButtonStyle.DEFAULT,
          primary: true,
          action: (): void => {
            void this.saveFile(true);
          }
        }
      ],
      cancel: (): void => {},
      onWillDismiss: (dismissDialogAction: DismissDialogAction): void => {
        if (dismissDialogAction.reason === DismissReason.PRESS_BACK ||
          dismissDialogAction.reason === DismissReason.TOUCH_OUTSIDE) {
          dismissDialogAction.dismiss();
        }
      }
    });
  }

  aboutToDisappear(): void {
    this.flushRecovery();
    if (this.recoveryTimer >= 0) clearTimeout(this.recoveryTimer);
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
    const heading: HdsNavigationTitle = { mainTitle: this.title };
    const menu: HdsNavigationMenuContentOptions = {
      maxCount: 4,
      value: [
        // Keep the document actions in one navigation menu; find remains in the overflow menu.
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
    if (this.formatBarWanted()) {
      // 官方导航自定义区域：标题栏负责底部区域布局和安全区。
      // https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-navigation-customized-area
      content.bottomBuilder = { builder: (): void => this.TopFormatBar() };
    }
    return scrollingTitleBar(content);
  }

  private openDocumentMenu(): void {
    menuBridge.openDocumentMenu();
  }

  private currentFormat(): DocumentFormat {
    return DocumentService.formatFor(this.info);
  }

  /** Bind HDS navigation effects to the shared Scroll surface(s) in the active tab. */
  private activeScrollers(): Scroller[] {
    if (this.wide && this.selectedTab === this.splitTab()) {
      return [this.splitEditScroller, this.splitPreviewScroller];
    }
    if (this.currentFormat().outline && this.selectedTab === TAB_OUTLINE) return [this.outlineScroller];
    if (this.selectedTab === TAB_EDIT) return [this.editScroller];
    return [this.previewScroller];
  }

  private isDirty(): boolean {
    return this.source !== this.savedText;
  }

  /**
   * 离开前只要正文和上次保存不同，就先问用户。不因为文件可写就直接写回。
   * 草稿副本只用于崩溃兜底，不再作为「未保存」的常驻入口。
   */
  private async saveBeforeLeaving(): Promise<boolean> {
    if (!DocumentService.current().editing || !this.isDirty()) return true;
    return await this.askSaveOrDiscard();
  }

  /**
   * 未保存的退出确认。问句只留一句。
   * 《警告弹窗》里两个及以下按钮在 AUTO 下水平排布，这里显式用 HORIZONTAL：
   * 数组第一项在左，第二项在右。两边都用 DialogButtonStyle.DEFAULT（白底蓝字，
   * 深色主题为黑底蓝字），不改字色，也不用 HIGHLIGHT（那是蓝底白字）。
   * 没有取消按钮。onWillDismiss 拦截侧滑、返回键和点击遮罩，关闭后留在文稿。
   * 侧滑和返回键的 reason 是 PRESS_BACK（ts-methods-alert-dialog-box，DismissReason）。
   */
  private askSaveOrDiscard(): Promise<boolean> {
    const saveLabel = this.info.uri.length > 0 && !this.info.writable ? '另存为' : '保存';
    return new Promise<boolean>((resolve: (leave: boolean) => void) => {
      let settled = false;
      const finish = (leave: boolean): void => {
        if (settled) return;
        settled = true;
        resolve(leave);
      };
      this.getUIContext().showAlertDialog({
        message: '是否保存更改？',
        autoCancel: true,
        buttonDirection: DialogButtonDirection.HORIZONTAL,
        buttons: [
          {
            value: '不保存',
            style: DialogButtonStyle.DEFAULT,
            action: (): void => finish(true)
          },
          {
            value: saveLabel,
            style: DialogButtonStyle.DEFAULT,
            primary: true,
            action: (): void => {
              this.saveFile(this.info.uri.length > 0 && !this.info.writable)
                .then((saved: boolean) => finish(saved))
                .catch(() => finish(false));
            }
          }
        ],
        cancel: (): void => finish(false),
        onWillDismiss: (dismissDialogAction: DismissDialogAction): void => {
          if (dismissDialogAction.reason === DismissReason.PRESS_BACK ||
            dismissDialogAction.reason === DismissReason.TOUCH_OUTSIDE) {
            dismissDialogAction.dismiss();
            finish(false);
          }
        }
      });
    });
  }

  private syncFromService(): void {
    const session = DocumentService.current();
    this.info = session.info;
    this.title = session.info.name;
    this.formatId = session.info.formatId;
    this.source = session.source;
    this.savedText = session.savedText;
    this.updateHeadings();
  }

  /** Build outline rows with the FAQ's List/ListItem tree pattern. TreeView has no documented
   * content-start offset and its API warns against generic attributes, so List owns this viewport. */
  private updateHeadings(): void {
    this.parseRevision++;
    this.headings = DocumentService.nativeHeadingsFor(this.info, this.source);
  }

  private acceptTexOutline(revision: number, headings: Heading[]): void {
    if (this.formatId === 'tex-math' && revision === this.parseRevision) this.headings = headings;
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
    this.updateHeadings();
    const position = caret >= 0 ? caret : this.selectionEnd;
    this.history.record(text, position, Date.now());
    this.refreshHistoryState();
    this.scheduleRecovery();
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
    this.updateHeadings();
    this.refreshHistoryState();
    this.scheduleRecovery();
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
  private EditPage(scroller: Scroller) {
    DocumentScrollLayer({ scroller: scroller }) {
      Column() {
        if (this.searchVisible) {
          this.FindBar()
        }
        TextArea({ text: this.source, placeholder: '在这里开始写作…', controller: this.cursor })
          .width('100%')
          .padding({
            top: 0,
            right: 16,
            bottom: 8,
            left: 16
          })
          // Keep the official ArkUI TextArea, with a transparent fill and the system no-corner resource
          // so the editor surface remains the same page background instead of a separate card.
          .backgroundColor(Color.Transparent)
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
      .backgroundColor($r('sys.color.ohos_id_color_background'))
    }
  }

  private splitTab(): number {
    return this.currentFormat().outline ? TAB_SPLIT : TAB_OUTLINE;
  }

  @Builder
  private TopFormatBar() {
    FormatBarView({
      formatId: this.formatId,
      onInsert: (action: InsertAction): void => this.insertToken(action)
    })
  }

  /** TabBarSymbol 使用独立的普通态和选中态；图标色需单独设置。 */
  private tabSymbol(symbol: Resource): TabBarSymbol {
    return {
      normal: new SymbolGlyphModifier(symbol).renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .fontColor([$r('sys.color.icon_primary')]),
      selected: new SymbolGlyphModifier(symbol).renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .fontColor([$r('sys.color.brand')])
    };
  }

  /** 华为 uiMaterial 沉浸材质示例：文字颜色使用可适配深浅色的系统资源。 */
  private bottomTab(symbol: Resource, label: string): BottomTabBarStyle {
    return BottomTabBarStyle.of(this.tabSymbol(symbol), label)
      .labelStyle({ selectedColor: $r('sys.color.brand'), unselectedColor: $r('sys.color.font_primary') });
  }

  @Builder
  private SplitPage() {
    RowSplit() {
      Column() { this.EditPage(this.splitEditScroller) }
        .width('50%')
        .height('100%')
      Column() {
        DocumentPreviewView({
          scroller: this.splitPreviewScroller, theme: this.theme, source: this.source,
          kind: this.currentFormat().id, parseRevision: this.parseRevision,
          onOutline: (revision: number, headings: Heading[]): void => this.acceptTexOutline(revision, headings)
        })
      }
        .width('50%')
        .height('100%')
    }
    // RowSplit (ts-container-rowsplit) supplies the divider; resizeable keeps its documented false default.
    .height('100%')
    .width('100%')
  }

  /**
   * @LocalBuilder, not @Builder: this subtree contains an if branch for the outline tab,
   * and a plain nested @Builder does not keep the state parent-child relationship, so that
   * branch would not rebuild when the state changes.
   *
   * 正文铺到标题栏和底部页签下面；两层控件悬浮在正文之上，且都不随键盘移动。
   */
  @LocalBuilder
  private WorkspacePage() {
    Stack() {
      HdsTabs({ barPosition: BarPosition.End, index: this.selectedTab }) {
        // Preview is first so a newly opened document lands on its rendered content.
        TabContent() {
          DocumentPreviewView({
            scroller: this.previewScroller, theme: this.theme, source: this.source,
            kind: this.currentFormat().id, parseRevision: this.parseRevision,
            onOutline: (revision: number, headings: Heading[]): void => this.acceptTexOutline(revision, headings)
          })
        }
          .attributeModifier(this.tabContentPolicy)
          .tabBar(this.bottomTab($r('sys.symbol.eye'), '预览'))
        TabContent() { this.EditPage(this.editScroller) }
          .attributeModifier(this.tabContentPolicy)
          .tabBar(this.bottomTab($r('sys.symbol.square_and_pencil'), '编辑'))
        // Only formats that declare an outline get the tab; plain text and SVG have none.
        if (this.currentFormat().outline) {
          TabContent() {
            DocumentOutlineView({
              headings: this.headings, scroller: this.outlineScroller,
              onSelect: (heading: Heading): void => this.focusHeading(heading)
            })
          }
            .attributeModifier(this.tabContentPolicy)
            .tabBar(this.bottomTab($r('sys.symbol.list_bullet'), '大纲'))
        }
        if (this.wide) {
          TabContent() { this.SplitPage() }
            .attributeModifier(this.tabContentPolicy)
            .tabBar(this.bottomTab($r('sys.symbol.rectangle_split_2x1'), '分栏'))
        }
      }
      // HdsTabs (ui-design-hdstabs)：存在 BottomTabBarStyle 时，未设置动画时长即使用官方默认值。
      .onChange((index: number) => {
        this.selectedTab = index;
        // 离开编辑页签就退出编辑态：键盘跟着收起，焦点不再挂在隐藏的 TextArea 上，
        // 回来时也不会把光标和键盘一起带回来。
        if (index !== TAB_EDIT && index !== this.splitTab()) this.stopEditing();
          })
      .barMode(BarMode.Fixed)
      // 按华为《沉浸光感》(ui-design-hds-component-material) 推荐值启用系统自适应材质。
      .barOverlap(true)
      .barFloatingStyle({
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
      .attributeModifier(this.tabsPolicy)
      .width('100%')
      .height('100%')
    }
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

  build() {
    HdsNavDestination() {
      this.WorkspacePage()
    }
    .titleBar(this.documentTitle())
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable(this.activeScrollers())
    .backgroundColor($r('sys.color.ohos_id_color_background'))
    // Keep the same destination layout contract as SettingsPage. HDS ignoreLayoutSafeArea
    // expands layout into the system avoid areas; it is not a paint-only transparency switch.
    // Scroll content extends through clipContent(SAFE_AREA) + PageTabsPolicy + PageTabContentPolicy.
    // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsnavdestination
    .onBackPressed(() => {
      this.requestLeave();
      return true;
    })
  }
}
