import { webview } from '@kit.ArkWeb';
import { Heading } from '../model/Document';
import { LocalImageRequest, openLocalImage, sourcesFromPage } from '../document/LocalImages';
import { AppText } from '../i18n/AppText';
import { i18n } from '@kit.LocalizationKit';
import { fileIo } from '@kit.CoreFileKit';
import { resourceLanguage } from '../i18n/AppLanguage';
import { PreviewCommand, PreviewCopy, PreviewDispatch } from './PreviewDispatch';
import { DocumentWebViewport, documentWebScroll, emptyDocumentViewport } from './DocumentScrollLayer';

interface ParsedHeading { level: number; text: string; offset: number }
interface ParsedResult {
  kind: string;
  revision: number;
  documentId?: number;
  headings: ParsedHeading[];
  url?: string;
}

const IMAGE_ORIGIN = 'https://images.marknote.invalid/';

/** 文稿预览和分栏预览共用同一组 Web 与滚动配置。 */
@Component
export struct DocumentPreviewView {
  @Prop @Watch('scheduleUpdate') theme: string = 'system';
  @Prop @Watch('scheduleUpdate') source: string = '';
  @Prop @Watch('scheduleUpdate') kind: string = 'markdown';
  @Prop @Watch('scheduleUpdate') parseRevision: number = 0;
  /** 当前文稿 URI。空字符串表示还没有文件，本地图片无法定位。 */
  @Prop @Watch('scheduleUpdate') documentUri: string = '';
  @Prop @Watch('scheduleUpdate') documentId: number = 0;
  /** off 不发送；outline 只让 LaTeX 回传大纲；render 才更新可见预览。 */
  @Prop @Watch('scheduleUpdate') workMode: string = 'off';
  /**
   * 界面语言。预览创建在 @Builder 里，按值传入的 language 不会更新。
   * 变化时重新发送预览文案，正文未变也要刷新占位和错误提示。
   * https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-builder
   */
  @StorageLink('marknote_language') @Watch('scheduleUpdate') language: string = 'default';
  @StorageLink('marknote_font_scale') fontScale: number = 1;
  @StorageLink('marknote_code_theme') @Watch('scheduleUpdate') codeTheme: string = 'github';
  onOutline: (documentId: number, revision: number, headings: Heading[]) => void =
    (_documentId: number, _revision: number, _headings: Heading[]): void => {};
  /** 预览里点击已校验的网页链接。页面不打开这个地址。 */
  onOpenExternalLink: (link: string) => void = (_link: string): void => {};
  @Prop @Watch('updateViewport') viewport: DocumentWebViewport = emptyDocumentViewport;
  private controller: webview.WebviewController = new webview.WebviewController();
  private ready: boolean = false;
  private hasPreviewContent: boolean = false;
  @State private previewFailed: boolean = false;
  private ports: webview.WebMessagePort[] = [];
  private timer: number = -1;
  private imageGeneration: number = 0;
  private renderedGeneration: number = -1;
  private viewportBusy: boolean = false;
  private viewportDirty: boolean = false;
  private imageRequests: Map<string, LocalImageRequest> = new Map();
  private imageQueue: Promise<void> = Promise.resolve();
  private dispatch: PreviewDispatch = new PreviewDispatch((command: PreviewCommand): Promise<void> => this.deliver(command));

  aboutToDisappear(): void {
    this.imageGeneration++;
    this.dispatch.dispose();
    if (this.timer >= 0) clearTimeout(this.timer);
    this.timer = -1;
    this.ready = false;
    if (this.ports.length > 1) {
      try { this.ports[1].close(); } catch { /* Web already released */ }
    }
    this.ports = [];
  }

  private connectResultPort(): void {
    try {
      if (this.ports.length > 1) this.ports[1].close();
      this.ports = this.controller.createWebMessagePorts();
      this.ports[1].onMessageEvent((message: webview.WebMessage): void => {
        if (typeof message !== 'string') return;
        try {
          const result = JSON.parse(message) as ParsedResult;
          if (result.kind === 'preview-layout') {
            if (result.revision === this.parseRevision && result.documentId === this.documentId) this.scheduleViewport();
            return;
          }
          if (result.kind === 'open-link') {
            const url = result.url;
            if (typeof url !== 'string' || url.length === 0) return;
            if (result.revision !== this.parseRevision || result.documentId !== this.documentId) return;
            if (this.kind !== 'markdown' || !this.ready) return;
            this.onOpenExternalLink(url);
            return;
          }
          if (result.kind !== 'tex-outline' || result.revision !== this.parseRevision ||
            result.documentId !== this.documentId ||
            this.kind !== 'tex-math' || !Array.isArray(result.headings)) return;
          const headings: Heading[] = [];
          for (const item of result.headings) {
            if (typeof item.text !== 'string' || typeof item.level !== 'number' ||
              typeof item.offset !== 'number' ||
              !Number.isInteger(item.offset) || item.offset < 0 || item.offset > this.source.length ||
              !Number.isInteger(item.level) || item.level < 1 || item.level > 6) return;
            headings.push(new Heading(item.level, item.text, item.offset));
          }
          this.onOutline(this.documentId, result.revision, headings);
        } catch { /* Ignore malformed results from the page. */ }
      });
      // 华为《建立应用侧与前端页面数据通道》：将一个端口转交网页。
      this.controller.postMessage('__marknote_parse_port__', [this.ports[0]], '*');
    } catch {
      this.ports = [];
    }
  }

  private scheduleUpdate(): void {
    this.imageGeneration++;
    this.imageRequests.clear();
    if (this.timer >= 0) clearTimeout(this.timer);
    this.timer = -1;
    if (this.workMode !== 'render' && this.hasPreviewContent) {
      this.hasPreviewContent = false;
      // Calls for this controller are queued after any render already sent.
      this.controller.runJavaScript('window.MarknotePreview.release()').catch((): void => {});
    }
    if (this.workMode === 'off') {
      this.dispatch.pause();
      return;
    }
    this.timer = setTimeout(() => {
      this.timer = -1;
      if (this.ready && this.workMode !== 'off') this.publish();
    }, 120);
  }

  private publish(): void {
    if (!this.ready || this.workMode === 'off') return;
    const lang = resourceLanguage(this.language);
    const copy: PreviewCopy = {
      lang, rtl: i18n.isRTL(lang),
      empty: AppText.text($r('app.string.preview_empty')),
      failed: AppText.text($r('app.string.preview_failed')),
      unsafe: AppText.text($r('app.string.preview_unsafe')),
      markdownFailed: AppText.text($r('app.string.preview_markdown_failed')),
      svgUnsafe: AppText.text($r('app.string.preview_svg_unsafe')),
      svgInvalid: AppText.text($r('app.string.preview_svg_invalid')),
      svgRejected: AppText.text($r('app.string.preview_svg_rejected')),
      mathFailed: AppText.text($r('app.string.preview_math_failed')),
      imageName: AppText.text($r('app.string.preview_image_name')),
      imageSlot: AppText.text($r('app.string.preview_image_slot')),
      scrollbarLabel: AppText.text($r('app.string.tab_preview'))
    };
    const payload: PreviewCommand = {
      kind: this.kind,
      source: this.source,
      theme: this.theme,
      codeTheme: this.codeTheme,
      revision: this.parseRevision,
      documentId: this.documentId,
      mode: this.workMode,
      text: copy
    };
    this.dispatch.request(payload);
    this.dispatch.resume();
  }

  private deliver(command: PreviewCommand): Promise<void> {
    if (command.mode !== this.workMode || command.documentId !== this.documentId ||
      command.revision !== this.parseRevision) return Promise.resolve();
    if (command.mode === 'render') this.hasPreviewContent = true;
    const script = 'window.MarknotePreview.update(' + JSON.stringify(command) + ')';
    const generation = this.imageGeneration;
    const current = (): boolean => this.ready && generation === this.imageGeneration && this.workMode === command.mode &&
      this.documentId === command.documentId && this.parseRevision === command.revision &&
      this.source === command.source && this.theme === command.theme && this.codeTheme === command.codeTheme;
    return this.controller.runJavaScript(script).then((): void => {
      if (current()) {
        this.previewFailed = false;
        this.renderedGeneration = generation;
        this.scheduleViewport();
      }
    }).catch((): void => {
      if (current()) this.previewFailed = true;
    });
  }

  private updateViewport(): void {
    if (!this.ready) return;
    this.controller.runJavaScript('window.MarknotePreview.setViewport(' + JSON.stringify(this.viewport) + ')')
      .then((): void => this.scheduleViewport()).catch((): void => {});
  }

  /** Even an unsaved document needs its visible Markdown blocks. */
  private scheduleViewport(): void {
    if (!this.ready || this.renderedGeneration !== this.imageGeneration || this.workMode !== 'render' ||
      this.kind !== 'markdown') return;
    this.viewportDirty = true;
    if (!this.viewportBusy) void this.refreshViewport();
  }

  private async refreshViewport(): Promise<void> {
    this.viewportBusy = true;
    try {
      while (this.viewportDirty && this.ready && this.renderedGeneration === this.imageGeneration &&
        this.workMode === 'render' && this.kind === 'markdown') {
        this.viewportDirty = false;
        const generation = this.imageGeneration;
        const raw = await this.controller.runJavaScript('JSON.stringify(window.MarknotePreview.imageWindow(' +
          generation + '))');
        if (generation !== this.imageGeneration || !this.ready) continue;
        const requests = this.documentUri ? sourcesFromPage(raw) : [];
        if (requests === null) continue;
        this.imageRequests.clear();
        for (const request of requests) this.imageRequests.set(IMAGE_ORIGIN + generation + '/' + request.id, request);
        if (requests.length) await this.controller.runJavaScript('window.MarknotePreview.loadImages(' + generation + ')');
      }
    } catch { /* The web component can be released during a viewport update. */ }
    finally { this.viewportBusy = false; }
  }

  // ArkWeb owns the descriptor after setResponseData. Only visible slots receive a URL.
  // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-basic-components-web-webresourceresponse/
  private imageResponse(event: OnInterceptRequestEvent): WebResourceResponse | null {
    const url = event.request.getRequestUrl();
    if (!url.startsWith(IMAGE_ORIGIN)) return null;
    const response = new WebResourceResponse();
    const request = this.imageRequests.get(url);
    const generation = this.imageGeneration;
    const current = (): boolean => this.ready && this.workMode === 'render' &&
      generation === this.imageGeneration && this.imageRequests.has(url);
    const missing = (): void => {
      response.setResponseCode(404);
      response.setReasonMessage('Not Found');
      response.setResponseData('');
    };
    if (!request || event.request.isMainFrame() || event.request.getRequestMethod() !== 'GET' || !current()) {
      missing();
      return response;
    }
    response.setResponseIsReady(false);
    // Serialize decoding so a page with many visible large images only prepares one thumbnail at a time.
    this.imageQueue = this.imageQueue.then(async (): Promise<void> => {
      try {
        const context = this.getUIContext().getHostContext();
        if (!current() || !context) { missing(); return; }
        const resource = await openLocalImage(this.documentUri, context.cacheDir, request);
        if (!resource) { missing(); return; }
        let transferred = false;
        try {
          if (!current()) { missing(); return; }
          response.setResponseMimeType(resource.mime);
          response.setResponseCode(200);
          response.setReasonMessage('OK');
          response.setResponseHeader([
            { headerKey: 'Cache-Control', headerValue: 'no-store' },
            { headerKey: 'X-Content-Type-Options', headerValue: 'nosniff' },
            { headerKey: 'Content-Security-Policy', headerValue: "sandbox; default-src 'none'; style-src 'unsafe-inline'; img-src data:" }
          ]);
          response.setResponseData(resource.file.fd);
          transferred = true;
          if (resource.intrinsicWidth > 0) {
            this.controller.runJavaScript('window.MarknotePreview.sizeImage(' +
              request.id + ',' + resource.intrinsicWidth + ',' + resource.intrinsicHeight + ')').catch((): void => {});
          }
        } finally {
          if (!transferred) await fileIo.close(resource.file);
        }
      } catch { missing(); }
      finally { response.setResponseIsReady(true); }
    }).catch((): void => {});
    return response;
  }

  @Builder
  private PreviewWeb() {
    Web({ src: $rawfile('preview/index.html'), controller: this.controller })
      .visibility(this.previewFailed ? Visibility.None : Visibility.Visible)
      // SDK documents null as pass-through for rawfile, although its callback type omits null.
      .onInterceptRequest((event) => this.imageResponse(event)!)
      .javaScriptAccess(true)
      .domStorageAccess(false)
      // ArkWeb 默认关闭深色模式；须在首次加载前设置，网页的 prefers-color-scheme 才能生效。
      // https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/web-set-dark-mode
      .darkMode(this.theme === 'system' ? WebDarkMode.Auto :
        (this.theme === 'dark' ? WebDarkMode.On : WebDarkMode.Off))
      // 兜底底色跟随页面底色（同一个系统 token），不写死黑白两色；
      // 预览正文的底色由 renderer 的样式表按主题决定。
      .backgroundColor($r('sys.color.ohos_id_color_background'))
      .textZoomRatio(Math.round(this.fontScale * 100))
      .attributeModifier(documentWebScroll)
      .onScroll((): void => this.scheduleViewport())
      .onAreaChange((): void => this.scheduleViewport())
      .onPageEnd(() => {
        this.imageGeneration++;
        this.imageRequests.clear();
        this.ready = true;
        this.connectResultPort();
        this.updateViewport();
        if (this.workMode !== 'off') this.publish();
      })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.PreviewWeb()
      if (this.previewFailed) {
        Text($r('app.string.preview_failed'))
          .padding({ top: this.viewport.top, left: this.viewport.start, right: this.viewport.end })
      }
    }
    .width('100%')
    .height('100%')
  }
}
