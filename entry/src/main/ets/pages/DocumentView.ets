import { common } from '@kit.AbilityKit';
import { FrameCallback, SymbolGlyphModifier, window } from '@kit.ArkUI';
import {
  HdsNavDestination, HdsNavDestinationTitleMode, HdsNavigationTitle,
  HdsNavigationIconOptions, HdsNavigationMenuItemOptions, HdsNavigationMenuContentOptions,
  TitleBarContentOptions, HdsNavigationTitleBarOptions, HdsTabs, hdsMaterial
} from '@kit.UIDesignKit';
import { DocumentInfo, Heading, RecoveryData } from '../model/Document';
import { DocumentService } from '../document/DocumentService';
import { DocumentShare } from '../document/DocumentShare';
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
import { searchFieldMaterial } from './ImmersiveMaterials';
import { LocalState } from '../storage/LocalState';
import { DocumentFiles } from '../storage/DocumentFiles';

/**
 * Tab positions on the document page. Preview comes first so a document opens in reading
 * view. Named constants keep the index arithmetic readable now that editing is not the first tab.
 */
const TAB_PREVIEW: number = 0;
const TAB_EDIT: number = 1;
const TAB_OUTLINE: number = 2;
const TAB_SPLIT: number = 3;

/** Run once after a rendered frame; used when a caret position needs layout to settle. */
class AfterFrame extends FrameCallback {
  private action: () => void;

  constructor(action: () => void) {
    super();
    this.action = action;
  }

  onIdle(_timeLeftInNano: number): void {
    this.action();
  }
}
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
  @Prop canExpand: boolean = false;
  @Prop expanded: boolean = false;
  @Prop favorite: boolean = false;
  onToggleExpanded: () => void = (): void => {};
  /** 每打开一篇就加一，用来在路由已经存在时重新载入会话。 */
  @Prop @Watch('loadSession') revision: number = 0;
  onLeave: () => void = (): void => {};
  /** 具有持久授权的文件保存成功后通知首页更新最近文稿。 */
  onSaved: (uri: string, name: string) => void = (_uri: string, _name: string): void => {};
  onDeleted: (uri: string) => void = (_uri: string): void => {};
  onToggleFavorite: (uri: string, name: string) => void = (_uri: string, _name: string): void => {};

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
  @State private deleting: boolean = false;
  @State private searchVisible: boolean = false;
  @State private query: string = '';
  @State private replacement: string = '';
  @State private currentMatch: number = -1;
  @State private matchCount: number = 0;
  @State private matchOrdinal: number = 0;
  @State private findBarHeight: number = 112;
  @State private searchControlsWidth: number = 80;
  /** Drives the enabled state of the title bar undo and redo icons. */
  @State private undoAvailable: boolean = false;
  @State private redoAvailable: boolean = false;
  private history: EditHistory = new EditHistory();
  private context: common.UIAbilityContext | null = null;
  private info: DocumentInfo = new DocumentInfo();
  private cursor: TextAreaController = new TextAreaController();
  private splitCursor: TextAreaController = new TextAreaController();
  private editTop: number = 0;
  private pendingHeadingOffset: number = -1;
  private headingJump: number = 0;
  private selectionStart: number = 0;
  private selectionEnd: number = 0;
  private recoveryTimer: number = -1;
  /**
   * 底部导航避让高度为 0 时，页签栏与 HdsTabs 底边留出一段应用自己的距离。
   * 这段用 sys.float.margin_left，不是华为规定的底边距；有导航避让区时不再加。
   */
  @Provide('documentNavigationInsetAbsent') private navigationInsetAbsent: boolean = false;
  private hostWindow: window.Window | null = null;
  private watchingIndicator: boolean = false;
  private readonly onAvoidArea = (data: window.AvoidAreaOptions): void => {
    if (data.type !== window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) return;
    this.navigationInsetAbsent = data.area.bottomRect.height === 0;
  };
  // 官方沉浸光感指南将 THIN 列为搜索框适用样式；不支持时保留系统输入框样式。
  private searchMaterial = searchFieldMaterial();
  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // 文稿页自己的菜单项：另存为和查找只对当前文稿有意义。
    menuBridge.saveAs = (): void => {
      menuBridge.dismiss((): void => { void this.saveFile(true); });
    };
    menuBridge.share = (): void => {
      menuBridge.dismiss((): void => { void this.shareDocument(); });
    };
    menuBridge.toggleFavorite = (): void => {
      menuBridge.dismiss((): void => this.toggleFavorite());
    };
    menuBridge.save = (): void => {
      menuBridge.dismiss((): void => { void this.saveFile(false); });
    };
    menuBridge.deleteDocument = (): void => {
      menuBridge.dismiss((): void => this.confirmDelete());
    };
    menuBridge.find = (): void => {
      menuBridge.dismiss((): void => {
        this.searchVisible = true;
        this.selectedTab = TAB_EDIT;
        this.currentMatch = -1;
        this.matchOrdinal = 0;
        this.matchCount = TextSearch.count(this.source, this.query);
      });
    };
    menuBridge.closeDocument = (): void => menuBridge.dismiss((): void => this.requestLeave());
    // 首页在换篇、返回列表前都要先问这里能否离开。
    documentBridge.saveBeforeLeaving = (): Promise<boolean> => this.saveBeforeLeaving();
    documentBridge.requestLeave = (): void => this.requestLeave();
    this.loadSession();
    this.watchNavigationIndicator();
    // 载入后再标记就绪，避免首页在正文同步前误判为没有未保存修改。
    documentBridge.markAttached();
  }

  /**
   * 《开发应用沉浸式效果》：全屏、悬浮窗、分屏切换会改变避让区，高度可以为 0。
   * 这里只判断高度是否为 0，高度单位是 px，不换算成 vp。
   * 注销时传入本次注册的回调，避免拆掉窗口上其他监听。
   */
  private watchNavigationIndicator(): void {
    if (!this.context) return;
    this.watchingIndicator = true;
    window.getLastWindow(this.context).then((host: window.Window) => {
      if (!this.watchingIndicator) return;
      this.hostWindow = host;
      const area = host.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.navigationInsetAbsent = area.bottomRect.height === 0;
      host.on('avoidAreaChange', this.onAvoidArea);
    }).catch(() => {
      // 读不到窗口时保持默认，不额外抬高底栏。
    });
  }

  private stopNavigationIndicator(): void {
    this.watchingIndicator = false;
    const host = this.hostWindow;
    this.hostWindow = null;
    if (host !== null) host.off('avoidAreaChange', this.onAvoidArea);
  }


  /** 窄屏收起分栏时回到预览，和之前媒体查询监听里的行为一致。 */
  private onWideChange(): void {
    if (!this.wide && this.selectedTab === this.splitTab()) this.selectedTab = TAB_PREVIEW;
  }

  /** 载入当前会话。首次进入和首页换篇（revision 变）都走这里。 */
  private loadSession(): void {
    this.headingJump++;
    this.pendingHeadingOffset = -1;
    this.syncFromService();
    // The history belongs to one document. Keeping it across a switch would let undo write
    // the previous document's text into this one.
    this.history.reset(this.source, 0);
    this.refreshHistoryState();
    this.currentMatch = -1;
    this.matchOrdinal = 0;
    this.matchCount = 0;
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
    this.stopNavigationIndicator();
    this.flushRecovery();
    if (this.recoveryTimer >= 0) clearTimeout(this.recoveryTimer);
    menuBridge.saveAs = (): void => {};
    menuBridge.share = (): void => {};
    menuBridge.toggleFavorite = (): void => {};
    menuBridge.save = (): void => {};
    menuBridge.deleteDocument = (): void => {};
    menuBridge.find = (): void => {};
    menuBridge.closeDocument = (): void => {};
    documentBridge.markDetached();
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

  private async shareDocument(): Promise<void> {
    if (!this.context) return;
    try {
      await DocumentShare.show(this.context, this.info.name, this.source);
    } catch {
      this.toast('无法分享文稿，请重试');
    }
  }

  private toggleFavorite(): void {
    if (this.info.uri.length === 0) {
      this.toast('请先保存文稿再收藏');
      return;
    }
    if (!this.info.persistent) {
      this.toast('当前文件无法长期访问，请另存为后收藏');
      return;
    }
    this.onToggleFavorite(this.info.uri, this.info.name);
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
    const more = this.menuIcon('更多', $r('sys.symbol.dot_grid_2x2'), 'marknote-doc-more',
      (): void => this.openDocumentMenu());
    const actions: HdsNavigationMenuItemOptions[] = this.inEditTab() ? [
      this.menuIcon('撤销', $r('sys.symbol.undo'), 'marknote-undo',
        (): void => this.undo(), this.undoAvailable),
      this.menuIcon('重做', $r('sys.symbol.redo'), 'marknote-redo',
        (): void => this.redo(), this.redoAvailable),
      more,
      this.menuIcon('保存', $r('sys.symbol.checkmark'), 'marknote-save',
        (): void => { void this.saveFile(false); })
    ] : [
      this.menuIcon('分享', $r('sys.symbol.share'), 'marknote-share',
        (): void => { void this.shareDocument(); }),
      this.menuIcon(this.favorite ? '取消收藏' : '收藏',
        this.favorite ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'), 'marknote-favorite',
        (): void => this.toggleFavorite()),
      this.menuIcon('删除', $r('sys.symbol.trash'), 'marknote-delete',
        (): void => this.confirmDelete(), this.info.uri.length > 0 && !this.deleting),
      more
    ];
    const menu: HdsNavigationMenuContentOptions = {
      maxCount: 4,
      value: actions
    };
    const content: TitleBarContentOptions = { title: heading, menu: menu };
    content.backIcon = {
      label: this.canExpand ? (this.expanded ? '恢复分栏' : '放大文稿') : '返回',
      icon: this.canExpand ?
        (this.expanded ? $r('sys.symbol.arrow_down_right_and_arrow_up_left') :
          $r('sys.symbol.arrow_up_left_and_arrow_down_right')) : $r('sys.symbol.chevron_backward'),
      action: (): void => {
        if (this.canExpand) this.onToggleExpanded();
        else this.requestLeave();
      }
    };
    if (this.searchVisible && this.selectedTab === TAB_EDIT) {
      // 搜索栏固定在导航标题下方，由 HDS 管理布局和组件安全区。
      // https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-navigation-customized-area
      content.bottomBuilder = { builder: (): void => this.FindBar(), height: this.findBarHeight };
    } else if (this.formatBarWanted()) {
      // 官方导航自定义区域：标题栏负责底部区域布局和安全区。
      // https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-navigation-customized-area
      content.bottomBuilder = { builder: (): void => this.TopFormatBar() };
    }
    return scrollingTitleBar(content);
  }

  private openDocumentMenu(): void {
    menuBridge.showDocumentActions = this.inEditTab();
    menuBridge.canDeleteDocument = this.info.uri.length > 0 && !this.deleting;
    menuBridge.favorite = this.favorite;
    menuBridge.openDocumentMenu();
  }

  private confirmDelete(): void {
    if (this.saving || this.deleting || this.info.uri.length === 0) return;
    const uri = this.info.uri;
    const confirmedSource = this.source;
    this.getUIContext().showAlertDialog({
      title: '删除文件',
      message: this.isDirty() ?
        '将文件移入回收站？未保存的修改将被丢弃。' : '将文件移入回收站？',
      buttons: [
        { value: '取消', action: (): void => {} },
        { value: '删除', action: (): void => { void this.deleteDocument(uri, confirmedSource); } }
      ]
    });
  }

  private async deleteDocument(uri: string, confirmedSource: string): Promise<void> {
    const session = DocumentService.current();
    if (this.deleting || this.saving || !session.editing || session.info.uri !== uri) return;
    if (this.source !== confirmedSource) {
      this.confirmDelete();
      return;
    }
    const sourceBefore = this.source;
    this.deleting = true;
    try {
      await DocumentFiles.moveToTrash(session.info);
      this.onDeleted(uri);
      if (DocumentService.current() === session && session.editing && session.info.uri === uri) {
        if (this.source !== sourceBefore) {
          // An edit arriving while the file manager was working becomes an unsaved document.
          session.info.uri = '';
          session.info.writable = false;
          session.info.persistent = false;
          session.info.fingerprint = '';
          session.savedText = this.source + '\n';
          this.savedText = session.savedText;
          this.scheduleRecovery();
          this.toast('文件已移入回收站，新修改请保存为新文件');
        } else {
          this.clearRecovery();
          DocumentService.close();
          this.onLeave();
          this.toast('文件已移入回收站');
        }
      }
    } catch (error) {
      this.toast('删除失败：' + String(error));
    } finally {
      this.deleting = false;
    }
  }

  private currentFormat(): DocumentFormat {
    return DocumentService.formatFor(this.info);
  }

  /** Bind HDS navigation effects to the shared Scroll surface(s) in the active tab. */
  private activeScrollers(): Scroller[] {
    if (this.wide && this.selectedTab === this.splitTab()) {
      return [this.splitPreviewScroller, this.splitEditScroller];
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
    if (this.deleting) return false;
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
        message: this.info.uri.length > 0 && !this.info.writable ? '原文件无法写入，是否另存更改？' : '是否保存更改？',
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

  /** Refresh native Markdown headings and invalidate older LaTeX parse results. */
  private updateHeadings(): void {
    this.parseRevision++;
    this.headings = DocumentService.nativeHeadingsFor(this.info, this.source);
  }

  private acceptTexOutline(revision: number, headings: Heading[]): void {
    if (this.formatId === 'tex-math' && revision === this.parseRevision) this.headings = headings;
  }

  private async saveFile(asNewFile: boolean): Promise<boolean> {
    if (!this.context || this.saving || this.deleting) return false;
    if (!asNewFile && this.info.uri.length > 0 && !this.info.writable) {
      this.offerSaveCopy('原文件无法写入，请另存为其他文件。');
      return false;
    }
    this.saving = true;
    try {
      const result = await DocumentService.save(this.context, asNewFile);
      this.syncFromService();
      if (!result.saved) return false;
      this.toast(result.message + (this.info.persistent ? '' : '。无法保留长期访问权限，未加入最近文稿'));
      if (!this.isDirty()) this.clearRecovery();
      else this.scheduleRecovery();
      // 最近文稿列表在首页，保存成功只通知过去。
      if (this.info.persistent) this.onSaved(this.info.uri, this.title);
      return !result.stillDirty;
    } catch (error) {
      this.scheduleRecovery();
      if (!asNewFile && this.info.uri.length > 0) {
        this.offerSaveCopy('保存失败：' + String(error) + '\n可另存为其他文件。');
      } else {
        this.toast('保存失败：' + String(error));
      }
      return false;
    } finally {
      this.saving = false;
    }
  }

  /** 使用系统警告弹窗提供另存选项，关闭弹窗时保留未保存的内容。 */
  private offerSaveCopy(message: string): void {
    this.getUIContext().showAlertDialog({
      message: message,
      buttons: [
        { value: '取消', action: (): void => {} },
        { value: '另存为', primary: true, action: (): void => { void this.saveFile(true); } }
      ]
    });
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
    this.matchOrdinal = 0;
    this.matchCount = this.searchVisible ? TextSearch.count(text, this.query) : 0;
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
    this.matchOrdinal = 0;
    this.matchCount = this.searchVisible ? TextSearch.count(step.text, this.query) : 0;
    this.updateHeadings();
    this.refreshHistoryState();
    this.scheduleRecovery();
    const caret = Math.min(step.caret, step.text.length);
    this.selectionStart = caret;
    this.selectionEnd = caret;
    setTimeout(() => this.activeCursor().caretPosition(caret), 20);
  }

  private findNext(forward: boolean = true): void {
    if (!this.query) return;
    this.selectedTab = TAB_EDIT;
    const hit: SearchHit | null = forward ? TextSearch.following(this.source, this.query, this.currentMatch) :
      TextSearch.preceding(this.source, this.query, this.currentMatch);
    if (hit === null) {
      this.currentMatch = -1;
      this.toast('没有找到匹配内容');
      return;
    }
    this.currentMatch = hit.start;
    this.matchOrdinal = TextSearch.count(this.source, this.query, hit.start) + 1;
    const query = this.query;
    const revision = this.revision;
    this.getUIContext().postFrameCallback(new AfterFrame((): void => {
      if (!this.searchVisible || this.selectedTab !== TAB_EDIT || this.revision !== revision ||
        this.query !== query || this.currentMatch !== hit.start) return;
      // TextArea 的文本选区需要组件获焦；编辑框随内容增高，因此由外层 Scroll 定位。
      // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-textarea
      this.getUIContext().getFocusController().requestFocus('marknote-main-editor');
      this.cursor.caretPosition(hit.start);
      this.getUIContext().postFrameCallback(new AfterFrame((): void => {
        if (!this.searchVisible || this.selectedTab !== TAB_EDIT || this.revision !== revision ||
          this.query !== query || this.currentMatch !== hit.start) return;
        const caret = this.cursor.getCaretOffset();
        if (caret && caret.index === hit.start) {
          this.editScroller.scrollTo({
            xOffset: 0,
            yOffset: Math.max(0, this.editTop + this.getUIContext().px2vp(caret.y)),
            animation: false
          });
        }
        this.cursor.setTextSelection(hit.start, hit.start + hit.length, { menuPolicy: MenuPolicy.HIDE });
      }));
    }));
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
    setTimeout(() => this.activeCursor().caretPosition(caret), 20);
  }

  private insertToken(action: InsertAction): void {
    const start = Math.min(this.selectionStart, this.selectionEnd);
    const end = Math.max(this.selectionStart, this.selectionEnd);
    const selected = this.source.slice(start, end);
    const changed = this.source.slice(0, start) + action.before + selected + action.after +
      this.source.slice(end);
    const position = start + action.before.length + selected.length;
    this.updateSource(changed, position);
    setTimeout(() => this.activeCursor().caretPosition(position), 20);
  }

  private activeCursor(): TextAreaController {
    return this.wide && this.selectedTab === this.splitTab() ? this.splitCursor : this.cursor;
  }

  private focusHeading(heading: Heading): void {
    this.headingJump++;
    this.pendingHeadingOffset = heading.offset;
    this.selectedTab = TAB_EDIT;
  }

  /**
   * TextArea 自适应内容高度，外层 Scroll 才是滚动容器。Tab 显示后先设置光标，
   * 再于后续帧读取光标相对输入框的像素坐标并转换为 Scroll 所需的 vp。
   * 官方文档：ts-universal-attributes-text-style 的 getCaretOffset、ts-container-scroll 的 scrollTo。
   */
  private jumpToPendingHeading(): void {
    if (this.pendingHeadingOffset < 0) return;
    const offset = this.pendingHeadingOffset;
    const jump = this.headingJump;
    this.pendingHeadingOffset = -1;
    this.getUIContext().postFrameCallback(new AfterFrame((): void => {
      if (jump !== this.headingJump || this.selectedTab !== TAB_EDIT) return;
      try {
        this.getUIContext().getFocusController().requestFocus('marknote-main-editor');
        this.cursor.caretPosition(offset);
      } catch {
        this.toast('无法定位标题，请重试');
        return;
      }
      this.getUIContext().postFrameCallback(new AfterFrame((): void => {
        if (jump !== this.headingJump || this.selectedTab !== TAB_EDIT) return;
        const caret = this.cursor.getCaretOffset();
        if (!caret || caret.index !== offset) {
          this.toast('无法定位标题，请重试');
          return;
        }
        this.editScroller.scrollTo({
          xOffset: 0,
          yOffset: Math.max(0, this.editTop + this.getUIContext().px2vp(caret.y)),
          animation: false
        });
      }));
    }));
  }

  /** 搜索框与结果导航共享系统材质；替换操作的右边缘与搜索区域对齐。 */
  @Builder
  private FindBar() {
    Column() {
      Row() {
        Stack({ alignContent: Alignment.End }) {
          Search({ value: this.query, placeholder: '查找文稿内容' })
            .onSubmit(() => this.findNext())
            .onChange((value: string) => {
              this.query = value;
              this.currentMatch = -1;
              this.matchOrdinal = 0;
              this.matchCount = TextSearch.count(this.source, value);
            })
            .width('100%')
            // 清除按钮由 Search 提供；仅有文字时为它预留位置。
            .cancelButton({ style: this.query.length > 0 ? CancelButtonStyle.CONSTANT : CancelButtonStyle.INVISIBLE })
            .padding({ right: this.query.length > 0 ? this.searchControlsWidth + 40 : 0 })
            .systemMaterial(this.searchMaterial)
          if (this.query.length > 0) {
            Row() {
              Text(this.matchOrdinal > 0 ? `${this.matchOrdinal}/${this.matchCount}` : `共 ${this.matchCount} 处`)
                .fontColor($r('sys.color.font_secondary'))
                .accessibilityText(this.matchOrdinal > 0 ?
                  `第 ${this.matchOrdinal} 处，共 ${this.matchCount} 处` : `共 ${this.matchCount} 处`)
              Button() {
                SymbolGlyph($r('sys.symbol.chevron_up'))
                  .fontColor([$r('sys.color.icon_primary')])
                  .fontSize(24)
              }
              .buttonStyle(ButtonStyleMode.TEXTUAL)
              .width(40)
              .height(40)
              .accessibilityText('上一处')
              .enabled(this.matchCount > 0)
              .onClick(() => this.findNext(false))
              Button() {
                SymbolGlyph($r('sys.symbol.chevron_down'))
                  .fontColor([$r('sys.color.icon_primary')])
                  .fontSize(24)
              }
              .buttonStyle(ButtonStyleMode.TEXTUAL)
              .width(40)
              .height(40)
              .accessibilityText('下一处')
              .enabled(this.matchCount > 0)
              .onClick(() => this.findNext())
            }
            .margin({ right: 40 })
            .onAreaChange((_oldArea: Area, newArea: Area) => {
              const width = parseFloat(String(newArea.width)) || 0;
              if (width > 0 && width !== this.searchControlsWidth) this.searchControlsWidth = width;
            })
          }
        }
        .layoutWeight(1)
        .margin({ right: $r('sys.float.padding_level4') })
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontColor([$r('sys.color.icon_primary')])
            .fontSize(24)
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        // 华为通用应用 UX 体验标准：交互热区不得小于 40vp × 40vp。
        .width(40)
        .height(40)
        .accessibilityText('关闭查找')
        .onClick(() => this.searchVisible = false)
      }
      .width('100%')
      Row() {
        Row() {
          TextInput({ text: this.replacement, placeholder: '替换为' })
            .onChange((value: string) => { this.replacement = value; })
            .layoutWeight(1)
            .margin({ right: $r('sys.float.padding_level4') })
            .systemMaterial(this.searchMaterial)
          Button('替换')
            .onClick(() => this.replaceMatch())
        }
        .layoutWeight(1)
        .margin({ right: $r('sys.float.padding_level4') })
        Blank().width(40)
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
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const height = parseFloat(String(newArea.height)) || 0;
      if (height > 0 && height !== this.findBarHeight) this.findBarHeight = height;
    })
  }

  @Builder
  private EditPage(scroller: Scroller, controller: TextAreaController, editorId: string) {
    DocumentScrollLayer({ scroller: scroller }) {
      Column() {
        TextArea({ text: this.source, placeholder: '在这里开始写作…', controller: controller })
          .id(editorId)
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            if (editorId === 'marknote-main-editor') {
              this.editTop = parseFloat(String(newArea.position.y)) || 0;
            }
          })
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
    Row() {
      Column() {
        DocumentPreviewView({
          scroller: this.splitPreviewScroller, theme: this.theme, source: this.source,
          kind: this.currentFormat().id, parseRevision: this.parseRevision, documentUri: this.info.uri,
          onOutline: (revision: number, headings: Heading[]): void => this.acceptTexOutline(revision, headings)
        })
      }
        .layoutWeight(1)
        .height('100%')
      Divider().vertical(true).height('100%')
      Column() { this.EditPage(this.splitEditScroller, this.splitCursor, 'marknote-split-editor') }
        .layoutWeight(1)
        .height('100%')
    }
    // RowSplit fixes divider positions after initialization; Row weights adapt to window resizing.
    // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-rowsplit
    // Permit both scroll surfaces to paint into the titlebar safe area.
    .clip(false)
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
            kind: this.currentFormat().id, parseRevision: this.parseRevision, documentUri: this.info.uri,
            onOutline: (revision: number, headings: Heading[]): void => this.acceptTexOutline(revision, headings)
          })
        }
          .attributeModifier(this.tabContentPolicy)
          .tabBar(this.bottomTab($r('sys.symbol.eye'), '预览'))
        TabContent() { this.EditPage(this.editScroller, this.cursor, 'marknote-main-editor') }
          .onWillShow(() => this.jumpToPendingHeading())
          .attributeModifier(this.tabContentPolicy)
          .tabBar(this.bottomTab($r('sys.symbol.square_and_pencil'), '编辑'))
        // Only formats that declare an outline get the tab; plain text and SVG have none.
        if (this.currentFormat().outline) {
          TabContent() {
            DocumentOutlineView({
              headings: this.headings, documentRevision: this.revision, scroller: this.outlineScroller,
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
      // barBottomMargin 是页签栏到 HdsTabs 底边的距离，默认 0。
      // 导航避让高度大于 0 时不设置，避免和组件已有的安全区扩展叠成两段。
      // 高度为 0 时用应用自己的边距，不是文档规定的底部间距。
      .barFloatingStyle({
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        },
        barBottomMargin: this.navigationInsetAbsent ? $r('sys.float.margin_left') : 0
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
    this.splitCursor.stopEditing();
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
