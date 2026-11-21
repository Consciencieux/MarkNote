import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { SubHeader } from '@kit.ArkUI';
import { pageScroll, pageScrollWithSectionHeader } from './PageScrollPolicy';
import { SettingsActionRow, SettingsGroupStyle, SettingsListRow } from './SettingsListRow';
import { SettingsReadingFrame } from './SettingsReadingFrame';
import { CODE_THEME_VALUES, LANGUAGE_VALUES, THEME_VALUES, codeThemeLabel, languageLabel, themeLabel } from './SettingsView';
import { LocalState } from '../storage/LocalState';
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
        .accessibilityLevel('no-hide-descendants')
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
  private groupStyle: SettingsGroupStyle = new SettingsGroupStyle();
  /** 路由名，同时就是这一页的 section。 */
  @Prop section: string = 'about';
  /** 当前主题和语言取值，和设置首页、Index 共用同一份状态。 */
  @Link theme: string;
  /** 导航页不会跟着首页的 @Link 重建，语言从 AppStorage 取。 */
  @StorageLink('marknote_language') language: string = 'default';
  @StorageLink('marknote_code_theme') codeTheme: string = 'github';
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

  private chooseCodeTheme(choice: string): void {
    const host = this.getUIContext().getHostContext();
    if (host === undefined) return;
    try {
      LocalState.writeCodeThemeSync(host as common.UIAbilityContext, choice);
      this.codeTheme = choice;
    } catch {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.theme_save_failed') });
    }
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
  private ThemeHeader() {
    // 卡片栅格已处理页面外边距，标题内边距和排版由 SubHeader 提供。
    SubHeader({ secondaryTitle: $r('app.string.settings_theme_group'), contentMargin: {} })
  }

  @Builder
  private InfoRow(title: ResourceStr, status: ResourceStr) {
    ListItem({ style: ListItemStyle.CARD }) {
      SettingsListRow({ title: title, value: status })
    }
  }

  /**
   * 每一段许可证单独占一个 ListItem，避免整篇原文挂在同一项里。
   * 版心与帮助、隐私相同，见 SettingsReadingFrame。
   */
  @Builder
  private LicenseBlock(body: ResourceStr) {
    ListItem() {
      SettingsReadingFrame() {
        Text(body)
          .attributeModifier(bodyText)
          .copyOption(CopyOptions.LocalDevice)
          .width('100%')
      }
    }
  }

  @Builder
  private FramedColumn() {
    SettingsReadingFrame() {
      Column({ space: $r('sys.float.padding_level8') }) {
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

  /** 长正文不放进设置行。字号和颜色走共用的正文样式。 */
  @Builder
  private Paragraph(body: string | Resource, copyable: boolean = false) {
    Text(body)
      .attributeModifier(bodyText)
      .copyOption(copyable ? CopyOptions.LocalDevice : CopyOptions.None)
  }

  @Builder
  private HelpSection(title: Resource, body: Resource) {
    Column({ space: $r('sys.float.padding_level4') }) {
      Text(title).attributeModifier(sectionTitle)
      this.Paragraph(body)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
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
      } else if (this.section === 'code-theme') {
        ListItemGroup({ style: ListItemGroupStyle.CARD, header: this.ThemeHeader() }) {}
          .backgroundColor(Color.Transparent)
          .padding($r('sys.float.padding_level0'))
        ListItemGroup({ style: ListItemGroupStyle.CARD }) {
          ForEach(CODE_THEME_VALUES, (choice: string) => {
            SettingsChoiceRow({ title: codeThemeLabel(choice), selected: this.codeTheme === choice,
              onSelect: (): void => this.chooseCodeTheme(choice) })
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
          SettingsActionRow({
            title: $r('app.string.settings_project_license'),
            onSelect: (): void => this.onOpen('project-license')
          })
          SettingsActionRow({
            title: $r('app.string.settings_third_party'),
            onSelect: (): void => this.onOpen('licenses')
          })
        }.attributeModifier(this.groupStyle)
      } else if (this.section === 'about') {
        ListItemGroup({ style: ListItemGroupStyle.CARD }) {
          this.InfoRow($r('app.string.about_name'), $r('app.string.EntryAbility_label'))
          this.InfoRow($r('app.string.about_version'),
            this.version.length > 0 ? this.version : $r('app.string.about_version_unavailable'))
          SettingsActionRow({
            title: $r('app.string.about_github'),
            onSelect: (): void => this.onOpenProject()
          })
          SettingsActionRow({
            title: $r('app.string.settings_licenses'),
            onSelect: (): void => this.onOpen('license-list')
          })
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
    .attributeModifier(this.section === 'code-theme' ? pageScrollWithSectionHeader : pageScroll)
    .width('100%')
    .height('100%')
  }
}
