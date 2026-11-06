import { webview } from '@kit.ArkWeb';
import { Heading } from '../model/Document';
import { DocumentScrollLayer } from './DocumentScrollLayer';

interface ParsedHeading { level: number; text: string; offset: number; line: number }
interface ParsedResult { kind: string; revision: number; headings: ParsedHeading[] }

/** 文稿预览和分栏预览共用同一组 Web 与滚动配置。 */
@Component
export struct DocumentPreviewView {
  @Prop @Watch('scheduleUpdate') theme: string = 'system';
  @Prop @Watch('scheduleUpdate') source: string = '';
  @Prop @Watch('scheduleUpdate') kind: string = 'markdown';
  @Prop @Watch('scheduleUpdate') parseRevision: number = 0;
  onOutline: (revision: number, headings: Heading[]) => void = (_revision: number, _headings: Heading[]): void => {};
  scroller: Scroller = new Scroller();
  private controller: webview.WebviewController = new webview.WebviewController();
  private ready: boolean = false;
  private ports: webview.WebMessagePort[] = [];
  private timer: number = -1;

  aboutToDisappear(): void {
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
          if (result.kind !== 'tex-outline' || result.revision !== this.parseRevision ||
            this.kind !== 'tex-math' || !Array.isArray(result.headings)) return;
          const headings: Heading[] = [];
          for (const item of result.headings) {
            if (typeof item.text !== 'string' || typeof item.level !== 'number' ||
              typeof item.offset !== 'number' || typeof item.line !== 'number' ||
              !Number.isInteger(item.offset) || item.offset < 0 || item.offset > this.source.length ||
              !Number.isInteger(item.level) || item.level < 1 || item.level > 6 ||
              !Number.isInteger(item.line) || item.line < 1) return;
            headings.push(new Heading(item.level, item.text, item.offset, item.line));
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
    if (this.timer >= 0) clearTimeout(this.timer);
    this.timer = setTimeout(() => {
      this.timer = -1;
      if (this.ready) this.sendUpdate();
    }, 120);
  }

  private sendUpdate(): void {
    const command = 'window.MarknotePreview.update(' + JSON.stringify({
      kind: this.kind,
      source: this.source,
      theme: this.theme,
      revision: this.parseRevision
    }) + ')';
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
        this.sendUpdate();
      })
      .width('100%')
      // 《Web组件大小自适应页面内容布局》：Web 按内容撑高，滚动交给外层 Scroll；
      // NEVER 关掉 Web 自己的过滚动，避免和 Scroll 抢边缘效果。
      .layoutMode(WebLayoutMode.FIT_CONTENT)
      .overScrollMode(OverScrollMode.NEVER)
  }

  build() {
    DocumentScrollLayer({ scroller: this.scroller }) {
      this.PreviewWeb()
    }
  }
}
