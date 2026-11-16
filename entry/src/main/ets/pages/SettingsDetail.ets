import { common } from '@kit.AbilityKit';
import { LengthMetrics } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { PageScrollPolicy } from './PageScrollPolicy';
import { SettingsGroupStyle, SettingsListRow } from './SettingsListRow';
import { LANGUAGE_VALUES, THEME_VALUES, languageLabel, themeLabel } from './SettingsView';
import { cachedLicenseText, loadLicenseText, splitLicenseText } from './LicenseText';
import { bodyText, sectionTitle } from './TextRoles';

/**
 * 许可证正文的懒加载数据源。只通知可见区域创建对应的 ListItem。
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-rendering-control-lazyforeach
 */
class LicenseChunks implements IDataSource {
  private items: string[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): string {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  replace(items: string[]): void {
    this.items = items;
    this.listeners.forEach((listener: DataChangeListener): void => {
      listener.onDataReloaded();
    });
  }
}

/**
 * 单选行不用 @Builder 传递 selected。官方规定两个及以上参数的 @Builder 不会随状态刷新。
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-builder
 */
@Component
struct SettingsChoiceRow {
  @Prop title: Resource = $r('app.string.settings');
  @Prop selected: boolean = false;
  onSelect: () => void = (): void => {};

  build() {
    ListItem({ style: ListItemStyle.CARD }) {
      SettingsListRow({ title: this.title, selected: this.selected })
    }
    .onClick(() => this.onSelect())
    .accessibilityGroup(true)
    .accessibilityText(this.title)
    .accessibilityRole(AccessibilityRoleType.RADIO)
    .accessibilityChecked(this.selected)
  }
}

/**
 * 设置的内容页，按 section 渲染外观、隐私说明、许可证、关于或使用帮助。
 *
 * 标题栏和返回键由外层 HdsNavDestination 提供，这里只排内容。设置通过 HdsNavigation 路由展示，
 * 见 Index 里 Destination 的说明。
 *
 * 列表单选参考华为组件体验示例 ListSingleSelection：整行选择、仅在已选行显示系统勾选。
 * 选中状态来自主题和语言，返回这一页时仍对应当前选项。
 */
@Component
export struct SettingsDetail {
  scroller: Scroller = new Scroller();
  private scrollPolicy: PageScrollPolicy<ListAttribute> = new PageScrollPolicy<ListAttribute>();
  private groupStyle: SettingsGroupStyle = new SettingsGroupStyle();
  /** 路由名，同时就是这一页的 section。 */
  @Prop section: string = 'about';
  /** 当前主题和语言取值，和设置首页、Index 共用同一份状态。 */
  @Link theme: string;
  /** 导航页不会跟着首页的 @Link 重建，语言从 AppStorage 取。 */
  @StorageLink('marknote_language') language: string = 'default';
  @Prop version: string = '';
  /** 许可证原文尚未读完时显示加载指示。失败时改显示对应的说明。 */
  @State private licenseLoading: boolean = false;
  @State private licenseFailed: boolean = false;
  private licenseChunks: LicenseChunks = new LicenseChunks();
  private disposed: boolean = false;
  onOpen: (section: string) => void = (_section: string): void => {};
  onOpenProject: () => void = (): void => {};
  onChooseTheme: (choice: string) => void = (_choice: string): void => {};
  onChooseLanguage: (choice: string) => void = (_choice: string): void => {};

  aboutToAppear(): void {
    if (!this.isLicenseSection()) return;
    const cached = cachedLicenseText(this.section);
    if (cached.length > 0) {
      this.licenseChunks.replace(splitLicenseText(cached));
      return;
    }
    this.licenseLoading = true;
    void this.readLicense();
  }

  aboutToDisappear(): void {
    this.disposed = true;
  }

  private isLicenseSection(): boolean {
    return this.section === 'licenses' || this.section === 'project-license';
  }

  private async readLicense(): Promise<void> {
    const section = this.section;
    try {
      const text = await loadLicenseText(section, (): Promise<string> => this.readLicenseFile(section));
      if (this.disposed || this.section !== section) return;
      this.licenseChunks.replace(splitLicenseText(text));
      this.licenseLoading = false;
    } catch {
      if (this.disposed || this.section !== section) return;
      this.licenseFailed = true;
      this.licenseLoading = false;
    }
  }

  /**
   * 页面已经打开后再读。getRawFileContent 直接返回 Promise<Uint8Array>。
   * https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-resource-manager
   */
  private async readLicenseFile(section: string): Promise<string> {
    const host = this.getUIContext().getHostContext();
    if (host === undefined) {
      throw new Error('missing context');
    }
    const context = host as common.UIAbilityContext;
    const path = section === 'project-license' ? 'licenses/LICENSE' : 'licenses/THIRD_PARTY_NOTICES.txt';
    try {
      const bytes = await context.resourceManager.getRawFileContent(path);
      return util.TextDecoder.create('utf-8').decodeToString(bytes);
    } catch (error) {
      throw error instanceof Error ? error : new Error('unreadable license');
    }
  }

  @Builder
  private InfoRow(title: ResourceStr, status: ResourceStr) {
    ListItem({ style: ListItemStyle.CARD }) {
      SettingsListRow({ title: title, value: status })
    }
  }

  @Builder
  private LinkRow(title: ResourceStr, action: () => void) {
    ListItem({ style: ListItemStyle.CARD }) {
      SettingsListRow({ title: title, showArrow: true })
    }
    .onClick(action)
  }

  /**
   * 每一段许可证单独占一个 ListItem，避免整篇原文挂在同一项里。
   * 栅格按华为《响应式布局》示例：12 列下按断点居中占 12/10/8 列，基础边距 24vp。
   * https://developer.huawei.com/consumer/cn/doc/doccenter-multi-device/bpta-multi-device-responsive-layout
   */
  @Builder
  private LicenseBlock(body: ResourceStr) {
    ListItem() {
      GridRow({ columns: 12, breakpoints: { reference: BreakpointsReference.ComponentSize } }) {
        GridCol({
          span: { xs: 12, sm: 12, md: 10, lg: 8 },
          offset: { xs: 0, sm: 0, md: 1, lg: 2 }
        }) {
          Text(body)
            .attributeModifier(bodyText)
            .copyOption(CopyOptions.LocalDevice)
            .width('100%')
        }
      }
      .width('100%')
      .padding({
        start: LengthMetrics.vp(24),
        end: LengthMetrics.vp(24)
      })
    }
  }

  @Builder
  private FramedColumn() {
    GridRow({ columns: 12, breakpoints: { reference: BreakpointsReference.ComponentSize } }) {
      GridCol({
        span: { xs: 12, sm: 12, md: 10, lg: 8 },
        offset: { xs: 0, sm: 0, md: 1, lg: 2 }
      }) {
        Column() {
          if (this.section === 'help') {
            this.HelpSection($r('app.string.help_open_title'), $r('app.string.help_open_body'))
            this.HelpSection($r('app.string.help_edit_title'), $r('app.string.help_edit_body'))
            this.HelpSection($r('app.string.help_format_title'), $r('app.string.help_format_body'))
            this.HelpSection($r('app.string.help_draft_title'), $r('app.string.help_draft_body'))
            this.HelpSection($r('app.string.help_feedback_title'), $r('app.string.help_feedback_body'))
          } else {
            this.Paragraph($r('app.string.privacy_body'))
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
    }
    .width('100%')
    .padding({
      start: LengthMetrics.vp(24),
      end: LengthMetrics.vp(24)
    })
  }

  /** 长正文不放进设置行。字号和颜色走共用的正文样式。 */
  @Builder
  private Paragraph(body: string | Resource, copyable: boolean = false) {
    Text(body)
      .attributeModifier(bodyText)
      .copyOption(copyable ? CopyOptions.LocalDevice : CopyOptions.None)
  }

  @Builder
  private HelpSection(title: Resource, body: Resource) {
    Text(title)
      .attributeModifier(sectionTitle)
    this.Paragraph(body)
  }

  build() {
    List({ scroller: this.scroller }) {
      if (this.section === 'appearance') {
        ListItemGroup({ style: ListItemGroupStyle.CARD }) {
          // 键固定为选项本身。主题变化时只更新选中状态，不重建这三行。
          // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-rendering-control-foreach
          ForEach(THEME_VALUES, (choice: string) => {
            SettingsChoiceRow({
              title: themeLabel(choice),
              selected: this.theme === choice,
              onSelect: (): void => this.onChooseTheme(choice)
            })
          }, (choice: string) => choice)
        }.attributeModifier(this.groupStyle)
      } else if (this.section === 'language') {
        ListItemGroup({ style: ListItemGroupStyle.CARD }) {
          ForEach(LANGUAGE_VALUES, (choice: string) => {
            SettingsChoiceRow({
              title: languageLabel(choice),
              selected: this.language === choice,
              onSelect: (): void => this.onChooseLanguage(choice)
            })
          }, (choice: string) => `${this.language}:${choice}`)
        }.attributeModifier(this.groupStyle)
      } else if (this.section === 'license-list') {
        ListItemGroup({ style: ListItemGroupStyle.CARD }) {
          this.LinkRow($r('app.string.settings_project_license'), () => this.onOpen('project-license'))
          this.LinkRow($r('app.string.settings_third_party'), () => this.onOpen('licenses'))
        }.attributeModifier(this.groupStyle)
      } else if (this.section === 'about') {
        ListItemGroup({ style: ListItemGroupStyle.CARD }) {
          this.InfoRow($r('app.string.about_name'), $r('app.string.EntryAbility_label'))
          this.InfoRow($r('app.string.about_version'),
            this.version.length > 0 ? this.version : $r('app.string.about_version_unavailable'))
          this.LinkRow($r('app.string.about_github'), () => this.onOpenProject())
          this.LinkRow($r('app.string.settings_licenses'), () => this.onOpen('license-list'))
        }.attributeModifier(this.groupStyle)
      } else if (this.isLicenseSection()) {
        if (this.licenseLoading) {
          ListItem() {
            Column() {
              // LoadingProgress 需要明确宽高，过大会让动效变形。
              // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-loadingprogress
              LoadingProgress()
                .width(32)
                .height(32)
                .color($r('sys.color.icon_secondary'))
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({
              top: $r('sys.float.padding_level8'),
              bottom: $r('sys.float.padding_level8')
            })
          }
        } else if (this.licenseFailed) {
          this.LicenseBlock(this.section === 'project-license' ?
            $r('app.string.license_project_failed') : $r('app.string.license_third_failed'))
        } else {
          LazyForEach(this.licenseChunks, (block: string) => {
            this.LicenseBlock(block)
          }, (_block: string, index: number) => index.toString())
        }
      } else {
        ListItem() {
          this.FramedColumn()
        }
      }
    }
    .attributeModifier(this.scrollPolicy)
    .width('100%')
    .height('100%')
  }
}
