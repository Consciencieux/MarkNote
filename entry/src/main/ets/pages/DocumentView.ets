import { common, OpenLinkOptions } from '@kit.AbilityKit';
import { url } from '@kit.ArkTS';
import { FrameCallback, LengthMetrics, SymbolGlyphModifier, window } from '@kit.ArkUI';
import {
  HdsNavDestination, HdsNavDestinationTitleMode, HdsNavigationTitle,
  HdsNavigationMenuItemOptions, HdsNavigationMenuContentOptions,
  TitleBarContentOptions, HdsNavigationTitleBarOptions, HdsTabs, hdsMaterial
} from '@kit.UIDesignKit';
import { DocumentInfo, Heading } from '../model/Document';
import { DocumentService, DocumentSession } from '../document/DocumentService';
import { DocumentShare } from '../document/DocumentShare';
import { DocumentFormat, InsertAction } from '../document/FormatRegistry';
import { SearchHit, TextSearch } from '../document/TextSearch';
import { AnalysisRequest, AnalysisResult, DocumentAnalysis } from '../document/DocumentAnalysis';
import { FormatBarView } from './FormatBarView';
import { DocumentFindBar } from './DocumentFindBar';
import { DocumentOutlineView } from './DocumentOutlineView';
import { DocumentPreviewView } from './DocumentPreviewView';
import { DocumentScrollLayer } from './DocumentScrollLayer';
import { DocumentCodeEditor, DocumentCodeEditorController } from './DocumentCodeEditor';
import { PageTabContentPolicy, PageTabsPolicy } from './PageScrollPolicy';
import { menuBridge } from './DocumentMenus';
import { documentBridge } from './DocumentBridge';
import { AppText } from '../i18n/AppText';
import { isRightToLeftLanguage, resourceLanguage } from '../i18n/AppLanguage';
import { shownDetail } from '../document/UserNotice';
import { scrollingTitleBar, navigationMenuIcon } from './HdsMaterialStyles';

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
  /** 文稿页在导航栈里，不跟随首页 @Link。语言从 AppStorage 取，查找栏和预览才会重取。 */
  @StorageLink('marknote_language') language: string = 'default';
  @StorageLink('marknote_code_theme') codeTheme: string = 'github';
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
  private splitPreviewScroller: Scroller = new Scroller();
  @State private title: string = AppText.text($r('app.string.file_untitled_md'));
  @State private source: string = '';
  @State private savedText: string = '';
  @State private selectedTab: number = TAB_PREVIEW;
  /** Format id of the open document, kept as state so the format bar rebuilds on switch. */
  @State private formatId: string = '';
  @State private headings: Heading[] = [];
  @State private parseRevision: number = 0;
  @State private documentSessionId: number = 0;
  @State private headingRevision: number = -1;
  @State private pageVisible: boolean = false;
  @State private previewShown: boolean = true;
  @State private outlineShown: boolean = false;
  @State private splitShown: boolean = false;
  @State private saving: boolean = false;
  @State private deleting: boolean = false;
  @State private searchVisible: boolean = false;
  @State private query: string = '';
  @State private replacement: string = '';
  @State private currentMatch: number = -1;
  @State private matchCount: number = 0;
  @State private matchOrdinal: number = 0;
  @State private findBarHeight: number = 112;
  /** Drives the enabled state of the title bar undo and redo icons. */
  @State private undoAvailable: boolean = false;
  @State private redoAvailable: boolean = false;
  private editor: DocumentCodeEditorController = new DocumentCodeEditorController();
  @State private editorSessionKey: number = 0;
  private context: common.UIAbilityContext | null = null;
  private info: DocumentInfo = new DocumentInfo();
  private pendingHeadingOffset: number = -1;
  private headingJump: number = 0;
  private selectionStart: number = 0;
  private selectionEnd: number = 0;
  private sessionOwner: DocumentSession | null = null;
  private analysis: DocumentAnalysis = new DocumentAnalysis((result: AnalysisResult): void => {
    this.applyAnalysis(result);
  });
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
        void this.flushAnalysis();
      });
    };
    menuBridge.closeDocument = (): void => menuBridge.dismiss((): void => this.requestLeave());
    // 首页在换篇、返回列表前都要先问这里能否离开。
    documentBridge.saveBeforeLeaving = (): Promise<boolean> => this.saveBeforeLeaving();
    documentBridge.resumeEditing = (): void => { this.editor.command({ action: 'resume' }); };
    documentBridge.requestLeave = (): void => this.requestLeave();
    this.loadSession();
    this.watchNavigationIndicator();
    // 这里只标记文稿数据载入完毕；实际可见由 HdsNavDestination.onShown 标记。
    documentBridge.markAttached();
    DocumentService.bindRecoveryError((sessionId: number, _error: Error): void => {
      const owner = this.sessionOwner;
      if (owner !== null && owner.id === sessionId && owner === DocumentService.current()) {
        this.toast($r('app.string.draft_write_failed'));
      }
    });
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
    if (!this.wide && this.selectedTab === this.splitTab()) {
      this.selectedTab = TAB_PREVIEW;
      this.splitShown = false;
      this.previewShown = true;
    }
  }

  /** 载入当前会话。首次进入和首页换篇（revision 变）都走这里。 */
  private loadSession(): void {
    this.analysis.cancel();
    this.headingJump++;
    this.pendingHeadingOffset = -1;
    this.syncFromService();
    DocumentService.activateSession(DocumentService.current());
    // The history belongs to one document. Keeping it across a switch would let undo write
    // the previous document's text into this one.
    this.undoAvailable = false;
    this.redoAvailable = false;
    this.currentMatch = -1;
    this.matchOrdinal = 0;
    this.matchCount = 0;
    this.selectionStart = 0;
    this.selectionEnd = 0;
    this.selectedTab = TAB_PREVIEW;
    this.previewShown = true;
    this.outlineShown = false;
    this.splitShown = false;
    // 新文档从预览开始，编辑区不应带着上一篇的光标或编辑态。
    this.stopEditing();
    this.searchVisible = false;
    const session = DocumentService.current();
    if (session.source === session.savedText) void DocumentService.clearRecovery(session, 'discarded');
    this.editorSessionKey++;
  }

  aboutToDisappear(): void {
    this.stopNavigationIndicator();
    this.analysis.cancel();
    DocumentService.unbindRecoveryError();
    void DocumentService.flushRecovery();
    menuBridge.saveAs = (): void => {};
    menuBridge.share = (): void => {};
    menuBridge.toggleFavorite = (): void => {};
    menuBridge.save = (): void => {};
    menuBridge.deleteDocument = (): void => {};
    menuBridge.find = (): void => {};
    menuBridge.closeDocument = (): void => {};
    documentBridge.markDetached();
    documentBridge.saveBeforeLeaving = (): Promise<boolean> => Promise.resolve(true);
    documentBridge.resumeEditing = (): void => {};
    documentBridge.requestLeave = (): void => {};
  }

  /** 先处理未保存的改动，再关闭会话并请首页弹栈；取消或草稿清不掉时留在原处。 */
  private requestLeave(): void {
    void this.closeToLibrary().then((left: boolean): void => {
      if (left) this.onLeave();
    }).catch((): void => {
      this.toast($r('app.string.draft_write_failed'));
    });
  }

  private toast(message: string | Resource): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  /** 再次确认协议、主机和凭据后交给系统，不让预览页面自己打开。 */
  private openExternalLink(link: string): void {
    if (!this.context || link.length === 0 || link.length > 2048) return;
    let parsed = '';
    try {
      const address = new url.URL(link);
      if ((address.protocol === 'http:' || address.protocol === 'https:') &&
        address.hostname.length > 0 && address.username.length === 0 && address.password.length === 0 &&
        address.href.length <= 2048) {
        parsed = address.href;
      }
    } catch {
      return;
    }
    if (parsed.length === 0) return;
    const options: OpenLinkOptions = { appLinkingOnly: false, hideFailureTipDialog: true };
    this.context.openLink(parsed, options).catch((): void => {
      this.toast($r('app.string.link_open_failed'));
    });
  }

  private async shareDocument(): Promise<void> {
    if (!this.context) return;
    if (!await this.editor.flush()) return;
    try {
      await DocumentShare.show(this.context, this.info.name, this.source);
    } catch {
      this.toast($r('app.string.share_failed'));
    }
  }

  private toggleFavorite(): void {
    if (this.info.uri.length === 0) {
      this.toast($r('app.string.favorite_save_first'));
      return;
    }
    if (!this.info.persistent) {
      this.toast($r('app.string.favorite_need_access'));
      return;
    }
    this.onToggleFavorite(this.info.uri, this.info.name);
  }

  /** 读取 language，使语言切换后标题栏、页签和查找栏重新取词。 */
  private uiText(resource: Resource): string {
    if (this.language.length === 0) return '';
    return AppText.text(resource);
  }

  private uiFormat(resource: Resource, first: string, second: string = ''): string {
    if (this.language.length === 0) return '';
    return AppText.format(resource, first, second);
  }

  private documentTitle(): HdsNavigationTitleBarOptions {
    // 读取 language，语言切换后重新构建标题栏里的查找栏。查找栏的计数是取好的字符串。
    if (this.language.length === 0) {
      return scrollingTitleBar({ title: { mainTitle: this.title } });
    }
    const heading: HdsNavigationTitle = { mainTitle: this.title };
    const more = navigationMenuIcon($r('app.string.menu_more'), $r('sys.symbol.dot_grid_2x2'), 'marknote-doc-more',
      (): void => this.openDocumentMenu());
    const actions: HdsNavigationMenuItemOptions[] = this.inEditTab() ? [
      navigationMenuIcon($r('app.string.menu_undo'), $r('sys.symbol.undo'), 'marknote-undo',
        (): void => this.undo(), this.undoAvailable),
      navigationMenuIcon($r('app.string.menu_redo'), $r('sys.symbol.redo'), 'marknote-redo',
        (): void => this.redo(), this.redoAvailable),
      more,
      navigationMenuIcon($r('app.string.menu_save'), $r('sys.symbol.checkmark'), 'marknote-save',
        (): void => { void this.saveFile(false); })
    ] : [
      navigationMenuIcon($r('app.string.menu_share'), $r('sys.symbol.share'), 'marknote-share',
        (): void => { void this.shareDocument(); }),
      navigationMenuIcon(this.favorite ? $r('app.string.menu_unfavorite') : $r('app.string.menu_favorite'),
        this.favorite ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'), 'marknote-favorite',
        (): void => this.toggleFavorite()),
      navigationMenuIcon($r('app.string.menu_delete'), $r('sys.symbol.trash'), 'marknote-delete',
        (): void => this.confirmDelete(), this.info.uri.length > 0 && !this.deleting),
      more
    ];
    const menu: HdsNavigationMenuContentOptions = {
      maxCount: 4,
      value: actions
    };
    const content: TitleBarContentOptions = { title: heading, menu: menu };
    content.backIcon = {
      label: this.canExpand ?
        (this.expanded ? $r('app.string.menu_restore_columns') : $r('app.string.menu_expand')) :
        $r('app.string.menu_back'),
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
      content.bottomBuilder = { builder: (): void => this.TopFindBar(), height: this.findBarHeight };
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
    void this.showDeleteConfirmation();
  }

  private async showDeleteConfirmation(): Promise<void> {
    if (this.saving || this.deleting || this.info.uri.length === 0) return;
    if (!await this.editor.flush()) return;
    const uri = this.info.uri;
    const confirmedSource = this.source;
    this.getUIContext().showAlertDialog({
      title: this.uiText($r('app.string.delete_title')),
      message: this.uiText(this.isDirty() ? $r('app.string.delete_dirty') : $r('app.string.delete_clean')),
      buttons: [
        { value: this.uiText($r('app.string.dialog_cancel')), action: (): void => {} },
        { value: this.uiText($r('app.string.menu_delete')), action: (): void => { void this.deleteDocument(uri, confirmedSource); } }
      ]
    });
  }

  private async deleteDocument(uri: string, confirmedSource: string): Promise<void> {
    const session = DocumentService.current();
    if (this.deleting || this.saving || !session.editing || session.info.uri !== uri) return;
    if (!await this.editor.flush(true) || DocumentService.current() !== session || !session.editing) {
      this.editor.command({ action: 'resume' });
      return;
    }
    if (this.source !== confirmedSource) {
      this.editor.command({ action: 'resume' });
      this.confirmDelete();
      return;
    }
    this.deleting = true;
    try {
      const result = await DocumentService.moveToTrash();
      if (!result.deleted || DocumentService.current() !== session) return;
      this.onDeleted(uri);
      if (result.retainedEdits) {
        this.syncFromService();
        this.toast($r('app.string.delete_trashed_dirty'));
      } else {
        this.onLeave();
        this.toast($r('app.string.delete_trashed'));
      }
    } catch (error) {
      this.toast(this.uiFormat($r('app.string.delete_failed'), shownDetail(error)));
    } finally {
      this.deleting = false;
      this.editor.command({ action: 'resume' });
    }
  }

  private currentFormat(): DocumentFormat {
    return DocumentService.formatFor(this.info);
  }

  /** Bind HDS navigation effects to the shared Scroll surface(s) in the active tab. */
  private activeScrollers(): Scroller[] {
    if (this.wide && this.selectedTab === this.splitTab()) {
      return [this.splitPreviewScroller, this.editScroller];
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
    if (this.deleting || this.saving) return false;
    if (DocumentService.current().editing && !await this.editor.flush(true)) {
      this.editor.command({ action: 'resume' });
      return false;
    }
    if (!DocumentService.current().editing || !this.isDirty()) return true;
    const accepted = await this.askSaveOrDiscard();
    if (!accepted) this.editor.command({ action: 'resume' });
    return accepted;
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
    const saveLabel = this.uiText(this.info.uri.length > 0 && !this.info.writable ?
      $r('app.string.menu_save_as') : $r('app.string.menu_save'));
    return new Promise<boolean>((resolve: (leave: boolean) => void) => {
      let settled = false;
      const finish = (leave: boolean): void => {
        if (settled) return;
        settled = true;
        resolve(leave);
      };
      this.getUIContext().showAlertDialog({
        message: this.uiText(this.info.uri.length > 0 && !this.info.writable ?
          $r('app.string.save_prompt_readonly') : $r('app.string.save_prompt')),
        autoCancel: true,
        buttonDirection: DialogButtonDirection.HORIZONTAL,
        buttons: [
          {
            value: this.uiText($r('app.string.discard')),
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
    const wasSplit = this.wide && this.selectedTab === this.splitTab();
    const wasOutline = this.currentFormat().outline && this.selectedTab === TAB_OUTLINE;
    const session = DocumentService.current();
    const sameText = this.sessionOwner === session && this.source === session.source;
    this.sessionOwner = session;
    this.info = session.info;
    this.title = session.info.name;
    this.formatId = session.info.formatId;
    this.source = session.source;
    this.savedText = session.savedText;
    this.parseRevision = session.revision;
    this.documentSessionId = session.id;
    if (!sameText) {
      this.headings = [];
      this.headingRevision = -1;
    }
    if (wasSplit) this.selectedTab = this.splitTab();
    else if (wasOutline && !this.currentFormat().outline) this.selectedTab = TAB_PREVIEW;
  }

  private acceptTexOutline(documentId: number, revision: number, headings: Heading[]): void {
    const session = DocumentService.current();
    if (this.formatId === 'tex-math' && documentId === session.id && revision === session.revision) {
      this.headings = headings;
      this.headingRevision = revision;
    }
  }

  private async saveFile(asNewFile: boolean): Promise<boolean> {
    if (!this.context || this.saving || this.deleting) return false;
    if (!asNewFile && this.info.uri.length > 0 && !this.info.writable) {
      this.offerSaveCopy(this.uiText($r('app.string.save_copy_readonly')));
      return false;
    }
    const owner = DocumentService.current();
    this.saving = true;
    try {
      if (!await this.editor.flush() || DocumentService.current() !== owner || !owner.editing) return false;
      const result = await DocumentService.save(this.context, asNewFile);
      if (DocumentService.current() !== owner || !owner.editing) return false;
      this.syncFromService();
      if (!result.saved) return false;
      const recentLimit = this.uiText($r('app.string.save_not_persistent'));
      const plainSaved = result.message === this.uiText($r('app.string.saved'));
      this.toast(this.info.persistent ? result.message :
        plainSaved ? recentLimit : `${result.message}\n${recentLimit}`);
      if (this.info.persistent) this.onSaved(this.info.uri, this.title);
      return !result.stillDirty;
    } catch (error) {
      if (DocumentService.current() !== owner || !owner.editing) return false;
      if (!asNewFile && this.info.uri.length > 0) {
        this.offerSaveCopy(this.uiFormat($r('app.string.save_failed_copy'), shownDetail(error)));
      } else {
        this.toast(this.uiFormat($r('app.string.save_failed'), shownDetail(error)));
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
        { value: this.uiText($r('app.string.dialog_cancel')), action: (): void => {} },
        { value: this.uiText($r('app.string.menu_save_as')), primary: true, action: (): void => { void this.saveFile(true); } }
      ]
    });
  }

  /**
   * 确认离开，再清理草稿。清理失败就留在文稿并提示。
   * 清理期间正文又变了，只再确认一次；之后仍清不掉或又有新编辑，就停止关闭。
   */
  private async closeToLibrary(): Promise<boolean> {
    if (!await this.saveBeforeLeaving()) return false;
    const owner = DocumentService.current();
    let confirmAgain = true;
    let closed = false;
    try {
    while (DocumentService.current() === owner && owner.editing) {
      const source = owner.source;
      let cleared = false;
      try {
        cleared = await DocumentService.clearRecovery(owner, 'discarded');
      } catch (_error) {
        this.toast($r('app.string.draft_write_failed'));
        return false;
      }
      if (DocumentService.current() !== owner || !owner.editing) return false;
      const interrupted = (!cleared || owner.source !== source) && owner.source !== owner.savedText;
      if (!interrupted) {
        DocumentService.close();
        closed = true;
        return true;
      }
      if (!confirmAgain) {
        this.toast($r('app.string.draft_write_failed'));
        return false;
      }
      confirmAgain = false;
      if (!await this.saveBeforeLeaving()) return false;
    }
    return false;
    } finally {
      if (!closed) this.editor.command({ action: 'resume' });
    }
  }

  private analysisRequest(): AnalysisRequest {
    const session = DocumentService.current();
    const request = new AnalysisRequest();
    request.sessionId = session.id;
    request.revision = session.revision;
    request.source = this.source;
    request.formatId = this.formatId;
    request.query = this.searchVisible ? this.query : '';
    request.needOutline = this.formatId === 'markdown' && this.outlineTabVisible();
    request.needCount = this.searchVisible && this.query.length > 0;
    return request;
  }

  private submitAnalysis(): void {
    this.analysis.schedule(this.analysisRequest());
  }

  private async flushAnalysis(): Promise<void> {
    const request = this.analysisRequest();
    if (this.outlineTabVisible() && this.formatId === 'markdown') request.needOutline = true;
    if (this.searchVisible) request.needCount = this.query.length > 0;
    this.applyAnalysis(await this.analysis.flush(request));
  }

  private applyAnalysis(result: AnalysisResult): void {
    const session = DocumentService.current();
    const query = this.searchVisible ? this.query : '';
    if (result.sessionId !== session.id || result.revision !== session.revision || result.query !== query) return;
    if (result.headings !== null) {
      this.headings = result.headings;
      this.headingRevision = result.revision;
    }
    if (result.matchCount !== null) this.matchCount = result.matchCount;
    else if (!this.searchVisible || this.query.length === 0) this.matchCount = 0;
  }

  private outlineTabVisible(): boolean {
    return this.currentFormat().outline && this.selectedTab === TAB_OUTLINE;
  }

  private mainWorkMode(): string {
    if (!this.pageVisible || this.splitWorkMode() === 'render') return 'off';
    if (this.selectedTab === TAB_PREVIEW && this.previewShown) return 'render';
    if (this.outlineTabVisible() && this.outlineShown && this.formatId === 'tex-math') return 'outline';
    return 'off';
  }

  private splitWorkMode(): string {
    if (this.pageVisible && this.wide && this.selectedTab === this.splitTab() && this.splitShown) return 'render';
    return 'off';
  }

  /** Apply the editor's confirmed text to the active document service. */
  private updateSource(text: string, anchor: number, head: number): void {
    if (this.sessionOwner !== DocumentService.current() || !DocumentService.current().editing) return;
    const changed = DocumentService.edit(text);
    this.source = text;
    this.selectionStart = anchor;
    this.selectionEnd = head;
    this.currentMatch = -1;
    this.matchOrdinal = 0;
    if (changed) {
      this.parseRevision = DocumentService.current().revision;
      this.submitAnalysis();
    }
  }

  private undo(): void { this.editor.command({ action: 'undo' }); }
  private redo(): void { this.editor.command({ action: 'redo' }); }

  private findNext(forward: boolean = true): void {
    if (!this.query) return;
    this.selectedTab = TAB_EDIT;
    const hit: SearchHit | null = forward ? TextSearch.following(this.source, this.query, this.currentMatch) :
      TextSearch.preceding(this.source, this.query, this.currentMatch);
    if (hit === null) {
      this.currentMatch = -1;
      this.toast($r('app.string.no_match'));
      return;
    }
    this.currentMatch = hit.start;
    this.matchOrdinal = TextSearch.count(this.source, this.query, hit.start) + 1;
    const query = this.query;
    const revision = this.revision;
    this.getUIContext().postFrameCallback(new AfterFrame((): void => {
      if (this.searchVisible && this.query === query && this.revision === revision &&
        this.currentMatch === hit.start && this.selectedTab === TAB_EDIT) {
        this.editor.command({ action: 'select', anchor: hit.start, head: hit.start + hit.length });
      }
    }));
  }

  private replaceMatch(): void {
    if (!this.query) return;
    const start = this.currentMatch;
    if (TextSearch.replaceAt(this.source, start, this.query, this.replacement) === null) {
      this.findNext();
      return;
    }
    this.editor.command({ action: 'replace', from: start, to: start + this.query.length,
      expected: this.query, text: this.replacement });
    this.currentMatch = -1;
  }

  private insertToken(action: InsertAction): void {
    this.editor.command({ action: 'insert', id: action.id, before: action.before, after: action.after });
  }

  private focusHeading(heading: Heading): void {
    if (this.headingRevision !== DocumentService.current().revision) return;
    if (heading.offset < 0 || heading.offset > this.source.length) return;
    this.pendingHeadingOffset = heading.offset;
    this.selectedTab = TAB_EDIT;
  }

  private jumpToPendingHeading(): void {
    if (this.pendingHeadingOffset < 0) return;
    const offset = this.pendingHeadingOffset;
    this.pendingHeadingOffset = -1;
    if (this.headingRevision !== DocumentService.current().revision || offset > this.source.length) return;
    this.editor.command({ action: 'select', anchor: offset, head: offset });
  }

  @Builder
  private TopFindBar() {
    DocumentFindBar({
      query: this.query,
      replacement: this.replacement,
      matchCount: this.matchCount,
      matchOrdinal: this.matchOrdinal,
      onQueryChange: (value: string): void => {
        this.query = value;
        this.currentMatch = -1;
        this.matchOrdinal = 0;
        this.submitAnalysis();
      },
      onReplacementChange: (value: string): void => { this.replacement = value; },
      onNext: (): void => this.findNext(),
      onPrevious: (): void => this.findNext(false),
      onReplace: (): void => this.replaceMatch(),
      onClose: (): void => { this.searchVisible = false; },
      onHeightChange: (height: number): void => {
        if (height > 0 && height !== this.findBarHeight) this.findBarHeight = height;
      }
    })
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
  private bottomTab(symbol: Resource, label: ResourceStr): BottomTabBarStyle {
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
          documentId: this.documentSessionId, workMode: this.splitWorkMode(),
          onOutline: (documentId: number, revision: number, headings: Heading[]): void =>
            this.acceptTexOutline(documentId, revision, headings),
          onOpenExternalLink: (link: string): void => this.openExternalLink(link)
        })
      }
        .layoutWeight(1)
        .height('100%')
      Divider().vertical(true).height('100%')
      Column() { Blank() }
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
    Stack({ alignContent: Alignment.TopEnd }) {
      HdsTabs({ barPosition: BarPosition.End, index: this.selectedTab }) {
        // Preview is first so a newly opened document lands on its rendered content.
        TabContent() {
          DocumentPreviewView({
            scroller: this.previewScroller, theme: this.theme, source: this.source,
            kind: this.currentFormat().id, parseRevision: this.parseRevision, documentUri: this.info.uri,
            documentId: this.documentSessionId, workMode: this.mainWorkMode(),
            onOutline: (documentId: number, revision: number, headings: Heading[]): void =>
              this.acceptTexOutline(documentId, revision, headings),
            onOpenExternalLink: (link: string): void => this.openExternalLink(link)
          })
        }
          .onWillShow((): void => { this.previewShown = true; })
          .onWillHide((): void => { this.previewShown = false; })
          .attributeModifier(this.tabContentPolicy)
          .tabBar(this.bottomTab($r('sys.symbol.eye'), $r('app.string.tab_preview')))
        TabContent() { Column() { Blank() } }
          .onWillShow(() => this.jumpToPendingHeading())
          .attributeModifier(this.tabContentPolicy)
          .tabBar(this.bottomTab($r('sys.symbol.square_and_pencil'), $r('app.string.tab_edit')))
        // Only formats that declare an outline get the tab; plain text and SVG have none.
        if (this.currentFormat().outline) {
          TabContent() {
            DocumentOutlineView({
              headings: this.headings, documentRevision: this.revision, scroller: this.outlineScroller,
              onSelect: (heading: Heading): void => this.focusHeading(heading)
            })
          }
            .onWillShow((): void => {
              this.outlineShown = true;
              void this.flushAnalysis();
            })
            .onWillHide((): void => { this.outlineShown = false; })
            .attributeModifier(this.tabContentPolicy)
            .tabBar(this.bottomTab($r('sys.symbol.list_bullet'), $r('app.string.tab_outline')))
        }
        if (this.wide) {
          TabContent() { this.SplitPage() }
            .onWillShow((): void => { this.splitShown = true; })
            .onWillHide((): void => { this.splitShown = false; })
            .attributeModifier(this.tabContentPolicy)
            .tabBar(this.bottomTab($r('sys.symbol.rectangle_split_2x1'), $r('app.string.tab_split')))
        }
      }
      // HdsTabs (ui-design-hdstabs)：存在 BottomTabBarStyle 时，未设置动画时长即使用官方默认值。
      .onChange((index: number) => {
        this.selectedTab = index;
        // 离开编辑页签就退出编辑态：键盘跟着收起，焦点不再挂在隐藏的 TextArea 上，
        // 回来时也不会把光标和键盘一起带回来。
        if (index !== TAB_EDIT && index !== this.splitTab()) this.stopEditing();
        if (this.outlineTabVisible()) void this.flushAnalysis();
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
      // One Web instance remains mounted while editing and split tabs change.
      // Leave the floating tab bar uncovered so it retains its native interactions.
      Column() {
        ForEach([this.editorSessionKey], (key: number) => {
          DocumentScrollLayer({ scroller: this.editScroller }) {
            DocumentCodeEditor({
              sessionId: `document-${key}`, source: this.source, formatId: this.formatId,
              webTheme: this.theme, appearance: this.theme, theme: this.codeTheme,
              language: resourceLanguage(this.language),
              textDirection: this.language === 'default' ? 'auto' :
                (isRightToLeftLanguage(this.language) ? 'rtl' : 'ltr'),
              controller: this.editor,
              onChange: (source: string, anchor: number, head: number): void => {
                if (key === this.editorSessionKey) this.updateSource(source, anchor, head);
              },
              onRecover: (expected: string, source: string, anchor: number, head: number): boolean => {
                if (key !== this.editorSessionKey || this.sessionOwner !== DocumentService.current() ||
                  DocumentService.current().source !== expected) return false;
                this.updateSource(source, anchor, head);
                return true;
              },
              onState: (anchor: number, head: number, canUndo: boolean, canRedo: boolean): void => {
                if (key !== this.editorSessionKey) return;
                this.selectionStart = anchor;
                this.selectionEnd = head;
                this.undoAvailable = canUndo;
                this.redoAvailable = canRedo;
              },
              onConflict: (): void => { this.toast(this.uiFormat($r('app.string.save_failed'), '')); }
            })
          }
        }, (key: number): string => key.toString())
      }
      .width(this.wide && this.selectedTab === this.splitTab() ? '50%' : '100%')
      .height('calc(100% - 56vp)')
      .visibility(this.inEditTab() ? Visibility.Visible : Visibility.Hidden)
    }
    .width('100%')
    .height('100%')
  }

  /** 退出编辑态：收起键盘并放开焦点，用于离开编辑页签和关闭文稿。 */
  private stopEditing(): void {
    this.editor.command({ action: 'blur' });
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
    .onShown((): void => {
      this.pageVisible = true;
      documentBridge.markShown();
    })
    .onHidden((): void => {
      this.pageVisible = false;
      documentBridge.markHidden();
    })
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
