import { webview } from '@kit.ArkWeb';
import { Heading } from '../model/Document';
import { loadLocalImages, PreviewImage, sourcesFromPage } from '../document/LocalImages';
import { AppText } from '../i18n/AppText';
import { previewLanguageTag } from '../i18n/AppLanguage';
import { DocumentScrollLayer } from './DocumentScrollLayer';

interface ParsedHeading { level: number; text: string; offset: number }
interface ParsedResult { kind: string; revision: number; headings: ParsedHeading[] }
interface PreviewCopy {
  lang: string;
  empty: string;
  failed: string;
  unsafe: string;
  markdownFailed: string;
  svgUnsafe: string;
  svgInvalid: string;
  svgRejected: string;
  mathFailed: string;
  imageName: string;
  imageSlot: string;
}
interface PreviewCommand {
  kind: string;
  source: string;
  theme: string;
  revision: number;
  documentId: number;
  text: PreviewCopy;
}

/** 文稿预览和分栏预览共用同一组 Web 与滚动配置。 */
@Component
export struct DocumentPreviewView {
  @Prop @Watch('scheduleUpdate') theme: string = 'system';
  @Prop @Watch('scheduleUpdate') source: string = '';
  @Prop @Watch('scheduleUpdate') kind: string = 'markdown';
  @Prop @Watch('scheduleUpdate') parseRevision: number = 0;
  /** 当前文稿 URI。空字符串表示还没有文件，本地图片无法定位。 */
  @Prop @Watch('scheduleUpdate') documentUri: string = '';
  /** 界面语言。变化时重新发送预览文案，正文未变也要刷新占位和错误提示。 */
  @Prop @Watch('scheduleUpdate') language: string = 'default';
  onOutline: (revision: number, headings: Heading[]) => void = (_revision: number, _headings: Heading[]): void => {};
  scroller: Scroller = new Scroller();
  private controller: webview.WebviewController = new webview.WebviewController();
  private ready: boolean = false;
  private ports: webview.WebMessagePort[] = [];
  private timer: number = -1;
  private imageGeneration: number = 0;
  private imageTimer: number = -1;
  private imageBusy: boolean = false;
  private imageTop: number = 0;
  private imageHeight: number = 0;
  private failedImages: string[] = [];
  private publishedUri: string = '';
  private documentGeneration: number = 0;

  aboutToDisappear(): void {
    this.imageGeneration++;
    if (this.timer >= 0) clearTimeout(this.timer);
    if (this.imageTimer >= 0) clearTimeout(this.imageTimer);
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
          if (result.kind !== 'tex-outline' || result.revision !== this.parseRevision ||
            this.kind !== 'tex-math' || !Array.isArray(result.headings)) return;
          const headings: Heading[] = [];
          for (const item of result.headings) {
            if (typeof item.text !== 'string' || typeof item.level !== 'number' ||
              typeof item.offset !== 'number' ||
              !Number.isInteger(item.offset) || item.offset < 0 || item.offset > this.source.length ||
              !Number.isInteger(item.level) || item.level < 1 || item.level > 6) return;
            headings.push(new Heading(item.level, item.text, item.offset));
          }
          this.onOutline(result.revision, headings);
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
    this.failedImages = [];
    if (this.timer >= 0) clearTimeout(this.timer);
    this.timer = setTimeout(() => {
      this.timer = -1;
      if (this.ready) this.publish();
    }, 120);
  }

  private publish(): void {
    if (this.documentUri !== this.publishedUri) {
      this.publishedUri = this.documentUri;
      this.documentGeneration++;
    }
    this.sendUpdate();
    this.scheduleImages();
  }

  private scheduleImages(): void {
    this.imageGeneration++;
    if (this.imageTimer >= 0) clearTimeout(this.imageTimer);
    this.imageTimer = setTimeout(() => {
      this.imageTimer = -1;
      void this.refreshImages();
    }, 150);
  }

  /** 根据原生 Scroll 的可视范围逐张读取，避免一次持有整篇文稿的图片。 */
  private async refreshImages(): Promise<void> {
    if (this.imageBusy || !this.ready || this.kind !== 'markdown' || this.documentUri.length === 0 ||
      this.imageHeight <= 0) return;
    this.imageBusy = true;
    const generation = this.imageGeneration;
    const source = this.source;
    const uri = this.documentUri;
    try {
      const raw = await this.controller.runJavaScript('JSON.stringify(window.MarknotePreview.imageWindow(' +
        JSON.stringify(this.imageTop) + ',' + JSON.stringify(this.imageHeight) + '))');
      if (generation !== this.imageGeneration || source !== this.source || uri !== this.documentUri) return;
      const pending = sourcesFromPage(raw).filter((key: string): boolean => this.failedImages.indexOf(key) < 0);
      if (pending.length === 0) return;
      const key = pending[0];
      const images: PreviewImage[] = await loadLocalImages(uri, [key]);
      if (generation !== this.imageGeneration || source !== this.source || uri !== this.documentUri) return;
      if (images.length === 0) {
        this.failedImages.push(key);
      } else {
        await this.controller.runJavaScript('window.MarknotePreview.setImage(' + JSON.stringify(key) + ',' +
          JSON.stringify(images[0].dataUrl) + ')');
      }
      this.scheduleImages();
    } catch {
      // 页面已释放或图片不可用时，仍保留正文和图片占位。
    } finally {
      this.imageBusy = false;
      if (generation !== this.imageGeneration && this.imageTimer < 0 && this.ready) this.scheduleImages();
    }
  }

  private sendUpdate(): void {
    const copy: PreviewCopy = {
      lang: this.language === 'default' ? previewLanguageTag() : this.language,
      empty: AppText.text($r('app.string.preview_empty')),
      failed: AppText.text($r('app.string.preview_failed')),
      unsafe: AppText.text($r('app.string.preview_unsafe')),
      markdownFailed: AppText.text($r('app.string.preview_markdown_failed')),
      svgUnsafe: AppText.text($r('app.string.preview_svg_unsafe')),
      svgInvalid: AppText.text($r('app.string.preview_svg_invalid')),
      svgRejected: AppText.text($r('app.string.preview_svg_rejected')),
      mathFailed: AppText.text($r('app.string.preview_math_failed')),
      imageName: AppText.text($r('app.string.preview_image_name')),
      imageSlot: AppText.text($r('app.string.preview_image_slot'))
    };
    const payload: PreviewCommand = {
      kind: this.kind,
      source: this.source,
      theme: this.theme,
      revision: this.parseRevision,
      documentId: this.documentGeneration,
      text: copy
    };
    const command = 'window.MarknotePreview.update(' + JSON.stringify(payload) + ')';
    try {
      this.controller.runJavaScript(command);
    } catch {
      // Web 可能在切换页面时已经释放。
    }
  }

  @Builder
  private PreviewWeb() {
    // renderMode 是 Web 构造参数（web.d.ts 的 WebOptions，API 12 起），没有同名链式属性。
    // SYNC_RENDER 让 Web 作为画布节点和 ArkUI 一起绘制，FIT_CONTENT 才能按内容撑高。
    Web({ src: $rawfile('preview/index.html'), controller: this.controller, renderMode: RenderMode.SYNC_RENDER })
      .javaScriptAccess(true)
      .domStorageAccess(false)
      // ArkWeb 默认关闭深色模式；须在首次加载前设置，网页的 prefers-color-scheme 才能生效。
      // https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/web-set-dark-mode
      .darkMode(this.theme === 'system' ? WebDarkMode.Auto :
        (this.theme === 'dark' ? WebDarkMode.On : WebDarkMode.Off))
      // 兜底底色跟随页面底色（同一个系统 token），不写死黑白两色；
      // 预览正文的底色由 renderer 的样式表按主题决定。
      .backgroundColor($r('sys.color.ohos_id_color_background'))
      .onPageEnd(() => {
        this.ready = true;
        this.connectResultPort();
        this.publish();
      })
      .width('100%')
      // 《Web组件大小自适应页面内容布局》：Web 按内容撑高，滚动交给外层 Scroll；
      // NEVER 关掉 Web 自己的过滚动，避免和 Scroll 抢边缘效果。
      .layoutMode(WebLayoutMode.FIT_CONTENT)
      .overScrollMode(OverScrollMode.NEVER)
  }

  build() {
    DocumentScrollLayer({ scroller: this.scroller, onViewportChange: (top: number, height: number): void => {
      this.imageTop = top;
      this.imageHeight = height;
      this.scheduleImages();
    } }) {
      this.PreviewWeb()
    }
  }
}
